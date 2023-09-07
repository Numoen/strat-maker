import { amountAdd, readAndParse } from "reverse-mirage";
import type {
  ERC20,
  ERC20Amount,
  Fraction,
  ReverseMirageWrite,
} from "reverse-mirage";
import {
  type Account as ViemAccount,
  type Address,
  type Hex,
  type PublicClient,
  type WalletClient,
  encodeAbiParameters,
} from "viem";
import {
  calculateAccrue,
  calculateAddLiquidity,
  calculateBorrowLiquidity,
  calculateRemoveLiquidity,
  calculateRepayLiquidity,
  calculateSwap,
} from "./amounts.js";
import {
  CommandEnum,
  RouterAddress,
  SwapTokenSelectorEnum,
  TokenSelectorEnum,
} from "./constants.js";
import { routerABI } from "./generated.js";
import { type PositionData, dataID } from "./positions.js";
import { engineGetPair, engineGetStrike } from "./reads.js";
import type { Command, OrderType, PairData, Strike } from "./types.js";
import { fractionToQ128, getPairID } from "./utils.js";

// TODO: write directly to engine when doing actions that don't require payment

export const routerRoute = async (
  publicClient: PublicClient,
  walletClient: WalletClient,
  userAccount: ViemAccount | Address,
  args: {
    to: Address;
    commands: Command[];
    nonce: bigint;
    deadline: bigint;
    slippage: Fraction;
  },
): Promise<ReverseMirageWrite<typeof routerABI, "route">> => {
  const blockNumber = await publicClient.getBlockNumber();
  const account: Account = { tokens: [], liquidityPositions: [] };

  const pairData: Record<string, PairData> = {};

  // calculate amounts
  for (const c of args.commands) {
    const id = `${c.inputs.pair.token0.address}_${c.inputs.pair.token1.address}_${c.inputs.pair.scalingFactor}`;
    if (pairData[id] === undefined) {
      pairData[id] = await readAndParse(
        engineGetPair(publicClient, {
          pair: c.inputs.pair,
        }),
      );
    }

    const loadStrike = async (strike: Strike) => {
      if (pairData[id]!.strikes[strike] !== undefined) return;
      const strikeData = await readAndParse(
        engineGetStrike(publicClient, {
          pair: c.inputs.pair,
          strike: strike,
        }),
      );
      pairData[id]!.strikes[strike] = strikeData;
    };
    if (c.command === "CreatePair") {
      // TODO": a pair that isn't created
    } else if (c.command === "AddLiquidity") {
      await loadStrike(c.inputs.strike);

      const { amount0, amount1, position } = calculateAddLiquidity(
        c.inputs.pair,
        pairData[id]!,
        blockNumber,
        c.inputs.strike,
        c.inputs.spread,
        c.inputs.amountDesired,
      );
      updateToken(account, amount0);
      updateToken(account, amount1);
      updateLiquidityPosition(account, position);
    } else if (c.command === "RemoveLiquidity") {
      await loadStrike(c.inputs.strike);

      const { amount0, amount1, position } = calculateRemoveLiquidity(
        c.inputs.pair,
        pairData[id]!,
        blockNumber,
        c.inputs.strike,
        c.inputs.spread,
        c.inputs.amountDesired,
      );
      updateToken(account, amount0);
      updateToken(account, amount1);
      updateLiquidityPosition(account, position);
    } else if (c.command === "BorrowLiquidity") {
      await loadStrike(c.inputs.strike);

      const { amount0, amount1, position } = calculateBorrowLiquidity(
        c.inputs.pair,
        pairData[id]!,
        blockNumber,
        c.inputs.strike,
        c.inputs.amountDesiredCollateral,
        c.inputs.amountDesiredDebt,
      );
      updateToken(account, amount0);
      updateToken(account, amount1);
      updateLiquidityPosition(account, position);
    } else if (c.command === "RepayLiquidity") {
      await loadStrike(c.inputs.strike);
      const { amount0, amount1, position } = calculateRepayLiquidity(
        c.inputs.pair,
        pairData[id]!,
        blockNumber,
        c.inputs.strike,
        c.inputs.selectorCollateral,
        c.inputs.liquidityGrowthLast,
        c.inputs.multiplier,
        c.inputs.amountDesired,
      );
      updateToken(account, amount0);
      updateToken(account, amount1);
      updateLiquidityPosition(account, position);
    } else if (c.command === "Swap") {
      const { amount0, amount1 } = calculateSwap(
        c.inputs.pair,
        pairData[id]!,
        c.inputs.amountDesired === "Token0Account"
          ? account.tokens.find((t) => t.token === c.inputs.pair.token0)!
          : c.inputs.amountDesired === "Token1Account"
          ? account.tokens.find((t) => t.token === c.inputs.pair.token1)!
          : c.inputs.amountDesired,
      );
      updateToken(account, amount0);
      updateToken(account, amount1);
    } else if (c.command === "Accrue") {
      calculateAccrue(
        pairData[id]!,
        blockNumber,
        pairData[id]!.strikeCurrent[0],
      );
    }
  }

  // filter amounts owed
  // const transferRequestsToken = Object.values(account.tokens)
  //   .filter((c) => amountGreaterThan(c, 0))
  //   .map((t) => ({
  //     ...t,
  //     amount: fractionQuotient(
  //       fractionMultiply(fractionAdd(args.slippage, 1), t.amount),
  //     ),
  //   }));
  // const transferRequestsLP = Object.values(account.liquidityPositions)
  //   .filter((lp) => lp.balance < 0n)
  //   .map((lp) => ({ ...lp, balance: -lp.balance }))
  //   .map((lp) => ({
  //     ...lp,
  //     balance: fractionQuotient(
  //       fractionMultiply(fractionAdd(args.slippage, 1), lp.balance),
  //     ),
  //   }));

  // build permit3 transfers

  // sign

  // send transaction
  const { request, result } = await publicClient.simulateContract({
    address: RouterAddress,
    abi: routerABI,
    functionName: "route",
    account: userAccount,
    args: [
      {
        to: args.to,
        commandInputs: args.commands.map((c) => ({
          command: CommandEnum[c.command],
          input: encodeInput(c, account),
        })),
        numTokens: BigInt(Object.values(account.tokens).length),
        numLPs: BigInt(
          Object.values(account.liquidityPositions).filter(
            (lp) => lp.balance < 0,
          ).length,
        ),
        signatureTransfer: {
          nonce: args.nonce,
          deadline: args.deadline,
          transferDetails: [],
        },
        signature: "0x",
      },
    ],
  });

  const hash = await walletClient.writeContract(request);

  return { hash, request, result };
};

type Account = {
  tokens: ERC20Amount<ERC20>[];
  liquidityPositions: PositionData<OrderType>[];
};

const updateToken = (account: Account, currencyAmount: ERC20Amount<ERC20>) => {
  for (let i = 0; i < account.tokens.length; i++) {
    if (account.tokens[i]!.token === currencyAmount.token) {
      account.tokens[i] = amountAdd(account.tokens[i]!, currencyAmount);

      break;
    } else if (account.tokens[i] === undefined) {
      account.tokens[i] = currencyAmount;
    }
  }
};

const updateLiquidityPosition = (
  account: Account,
  positionData: PositionData<OrderType>,
) => {
  for (let i = 0; i < account.liquidityPositions.length; i++) {
    if (
      dataID(account.liquidityPositions[i]!.token) ===
      dataID(positionData.token)
    ) {
      account.liquidityPositions[i]!.balance += positionData.balance;
    } else if (account.liquidityPositions[i] === undefined) {
      account.liquidityPositions[i] = positionData;
    }
  }
};

const encodeInput = (command: Command, account: Account): Hex =>
  command.command === "AddLiquidity"
    ? encodeAbiParameters(AddLiquidityParams, [
        command.inputs.pair.token0.address,
        command.inputs.pair.token1.address,
        command.inputs.pair.scalingFactor,
        command.inputs.strike,
        command.inputs.spread,
        command.inputs.amountDesired,
      ])
    : command.command === "RemoveLiquidity"
    ? encodeAbiParameters(RemoveLiquidityParams, [
        command.inputs.pair.token0.address,
        command.inputs.pair.token1.address,
        command.inputs.pair.scalingFactor,
        command.inputs.strike,
        command.inputs.spread,
        command.inputs.amountDesired,
      ])
    : command.command === "BorrowLiquidity"
    ? encodeAbiParameters(BorrowLiquidityParams, [
        command.inputs.pair.token0.address,
        command.inputs.pair.token1.address,
        command.inputs.pair.scalingFactor,
        command.inputs.strike,
        command.inputs.amountDesiredCollateral.token ===
        command.inputs.pair.token0
          ? TokenSelectorEnum.Token0
          : TokenSelectorEnum.Token1,
        command.inputs.amountDesiredCollateral.amount,
        command.inputs.amountDesiredDebt,
      ])
    : command.command === "RepayLiquidity"
    ? encodeAbiParameters(RepayLiquidityParams, [
        command.inputs.pair.token0.address,
        command.inputs.pair.token1.address,
        command.inputs.pair.scalingFactor,
        command.inputs.strike,
        TokenSelectorEnum[command.inputs.selectorCollateral],
        fractionToQ128(command.inputs.liquidityGrowthLast),
        fractionToQ128(command.inputs.multiplier),
        command.inputs.amountDesired,
      ])
    : command.command === "Swap"
    ? encodeAbiParameters(SwapParams, [
        command.inputs.pair.token0.address,
        command.inputs.pair.token1.address,
        command.inputs.pair.scalingFactor,
        command.inputs.amountDesired === "Token0Account" ||
        command.inputs.amountDesired === "Token1Account"
          ? SwapTokenSelectorEnum.Account
          : command.inputs.amountDesired.token === command.inputs.pair.token0
          ? SwapTokenSelectorEnum.Token0
          : SwapTokenSelectorEnum.Token1,
        command.inputs.amountDesired === "Token0Account"
          ? BigInt(
              account.tokens.findIndex(
                (a) => a.token === command.inputs.pair.token0,
              ),
            )
          : command.inputs.amountDesired === "Token1Account"
          ? BigInt(
              account.tokens.findIndex(
                (a) => a.token === command.inputs.pair.token1,
              ),
            )
          : command.inputs.amountDesired.amount,
      ])
    : command.command === "Accrue"
    ? encodeAbiParameters(AccrueParams, [
        getPairID(command.inputs.pair),
        command.inputs.strike,
      ])
    : encodeAbiParameters(CreatePairParams, [
        command.inputs.pair.token0.address,
        command.inputs.pair.token1.address,
        command.inputs.pair.scalingFactor,
        command.inputs.strike,
      ]);

export const SwapParams = [
  { name: "token0", type: "address" },
  { name: "token1", type: "address" },
  { name: "scalingFactor", type: "uint8" },
  { name: "selector", type: "uint8" },
  { name: "amountDesired", type: "int256" },
] as const;

export const AddLiquidityParams = [
  { name: "token0", type: "address" },
  { name: "token1", type: "address" },
  { name: "scalingFactor", type: "uint8" },
  { name: "strike", type: "int24" },
  { name: "spread", type: "uint8" },
  { name: "amountDesired", type: "uint128" },
] as const;

export const UnwrapWETHParams = [
  {
    name: "wethIndex",
    type: "uint256",
  },
];

export const RemoveLiquidityParams = [
  { name: "token0", type: "address" },
  { name: "token1", type: "address" },
  { name: "scalingFactor", type: "uint8" },
  { name: "strike", type: "int24" },
  { name: "spread", type: "uint8" },
  { name: "amountDesired", type: "uint128" },
] as const;

export const BorrowLiquidityParams = [
  { name: "token0", type: "address" },
  { name: "token1", type: "address" },
  { name: "scalingFactor", type: "uint8" },
  { name: "strike", type: "int24" },
  { name: "selectorCollateral", type: "uint8" },
  { name: "amountDesiredCollateral", type: "int256" },
  { name: "amountDesiredDebt", type: "uint128" },
] as const;

export const RepayLiquidityParams = [
  { name: "token0", type: "address" },
  { name: "token1", type: "address" },
  { name: "scalingFactor", type: "uint8" },
  { name: "strike", type: "int24" },
  { name: "selectorCollateral", type: "uint8" },
  { name: "liquidityGrowthLastX128", type: "uint256" },
  { name: "multiplierX128", type: "uint136" },
  { name: "amountDesired", type: "uint128" },
] as const;

export const AccrueParams = [
  { name: "pairID", type: "bytes32" },
  { name: "strike", type: "int24" },
] as const;

export const CreatePairParams = [
  { name: "token0", type: "address" },
  { name: "token1", type: "address" },
  { name: "scalingFactor", type: "uint8" },
  { name: "strikeInitial", type: "int24" },
] as const;
