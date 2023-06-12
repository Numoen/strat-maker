// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.19;

import {Pairs, MAX_TIERS} from "./Pairs.sol";
import {Ticks} from "./Ticks.sol";
import {Positions} from "./Positions.sol";

import {BalanceLib} from "src/libraries/BalanceLib.sol";
import {SafeTransferLib} from "src/libraries/SafeTransferLib.sol";

import {IAddLiquidityCallback} from "./interfaces/IAddLiquidityCallback.sol";
import {ISwapCallback} from "./interfaces/ISwapCallback.sol";

/// @author Robert Leifke and Kyle Scott
contract Engine is Positions {
    using Ticks for Ticks.Tick;
    using Pairs for Pairs.Pair;
    using Pairs for mapping(bytes32 => Pairs.Pair);

    event PairCreated(address indexed token0, address indexed token1, int24 tickInitial);
    event AddLiquidity();
    event RemoveLiquidity();
    event Swap();

    error InvalidTokenOrder();
    error InsufficientInput();

    mapping(bytes32 => Pairs.Pair) internal pairs;

    function createPair(address token0, address token1, int24 tickInitial) external {
        if (token0 >= token1 || token0 == address(0)) revert InvalidTokenOrder();

        Pairs.Pair storage pair = pairs.getPair(token0, token1);
        pair.initialize(tickInitial);

        emit PairCreated(token0, token1, tickInitial);
    }

    struct AddLiquidityParams {
        address token0;
        address token1;
        address to;
        uint8 tier;
        int24 tick;
        uint256 liquidity;
        bytes data;
    }

    function addLiquidity(AddLiquidityParams calldata params) external returns (uint256 amount0, uint256 amount1) {
        Pairs.Pair storage pair = pairs.getPair(params.token0, params.token1);
        (amount0, amount1) = pair.updateLiquidity(params.tier, params.tick, int256(params.liquidity));

        _mint(
            params.to,
            abi.encode(
                Positions.ILRTADataID({
                    token0: params.token0,
                    token1: params.token1,
                    tick: params.tick,
                    tier: params.tier
                })
            ),
            params.liquidity
        );

        uint256 balance0 = BalanceLib.getBalance(params.token0);
        uint256 balance1 = BalanceLib.getBalance(params.token1);
        IAddLiquidityCallback(msg.sender).addLiquidityCallback(amount0, amount1, params.data);
        if (BalanceLib.getBalance(params.token0) < balance0 + amount0) revert InsufficientInput();
        if (BalanceLib.getBalance(params.token1) < balance1 + amount1) revert InsufficientInput();

        emit AddLiquidity();
    }

    struct RemoveLiquidityParams {
        address token0;
        address token1;
        address to;
        uint8 tier;
        int24 tick;
        uint256 liquidity;
    }

    function removeLiquidity(RemoveLiquidityParams calldata params)
        external
        returns (uint256 amount0, uint256 amount1)
    {
        Pairs.Pair storage pair = pairs.getPair(params.token0, params.token1);
        (amount0, amount1) = pair.updateLiquidity(params.tier, params.tick, -int256(params.liquidity));

        SafeTransferLib.safeTransfer(params.token0, params.to, amount0);
        SafeTransferLib.safeTransfer(params.token1, params.to, amount1);

        _burn(
            msg.sender,
            abi.encode(
                Positions.ILRTADataID({
                    token0: params.token0,
                    token1: params.token1,
                    tick: params.tick,
                    tier: params.tier
                })
            ),
            params.liquidity
        );

        emit RemoveLiquidity();
    }

    struct SwapParams {
        address token0;
        address token1;
        address to;
        bool isToken0;
        int256 amountDesired;
        bytes data;
    }

    function swap(SwapParams calldata params) external returns (int256 amount0, int256 amount1) {
        Pairs.Pair storage pair = pairs.getPair(params.token0, params.token1);
        (amount0, amount1) = pair.swap(params.isToken0, params.amountDesired);

        if (params.isToken0 == (params.amountDesired > 0)) {
            if (amount1 < 0) SafeTransferLib.safeTransfer(params.token1, params.to, uint256(-amount1));
            uint256 balance0 = BalanceLib.getBalance(params.token0);
            ISwapCallback(msg.sender).swapCallback(amount0, amount1, params.data);
            if (BalanceLib.getBalance(params.token0) < balance0 + uint256(amount0)) revert InsufficientInput();
        } else {
            if (amount0 < 0) SafeTransferLib.safeTransfer(params.token0, params.to, uint256(-amount0));
            uint256 balance1 = BalanceLib.getBalance(params.token1);
            ISwapCallback(msg.sender).swapCallback(amount0, amount1, params.data);
            if (BalanceLib.getBalance(params.token1) < balance1 + uint256(amount1)) revert InsufficientInput();
        }

        emit Swap();
    }

    function getPair(
        address token0,
        address token1
    )
        external
        view
        returns (uint128[MAX_TIERS] memory compositions, int24 tickCurrent, int8 offset, uint8 lock)
    {
        Pairs.Pair storage pair = pairs.getPair(token0, token1);
        (compositions, tickCurrent, offset, lock) = (pair.compositions, pair.tickCurrent, pair.offset, pair.lock);
    }

    function getTick(address token0, address token1, int24 tick) external view returns (Ticks.Tick memory) {
        return pairs.getPair(token0, token1).ticks[tick];
    }

    function getPosition(
        address token0,
        address token1,
        address owner,
        uint8 tier,
        int24 tick
    )
        external
        view
        returns (Positions.ILRTAData memory)
    {
        return _dataOf[dataID(
            owner, abi.encode(Positions.ILRTADataID({token0: token0, token1: token1, tick: tick, tier: tier}))
        )];
    }
}
