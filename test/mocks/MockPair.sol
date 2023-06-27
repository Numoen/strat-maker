// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Pairs, NUM_SPREADS} from "src/core/Pairs.sol";
import {Positions} from "src/core/Positions.sol";
import {toInt256} from "src/core/math/LiquidityMath.sol";

import {BalanceLib} from "src/libraries/BalanceLib.sol";
import {SafeTransferLib} from "src/libraries/SafeTransferLib.sol";

import {IExecuteCallback} from "src/core/interfaces/IExecuteCallback.sol";

contract MockPair is Positions {
    using Pairs for Pairs.Pair;

    address private immutable token0;
    address private immutable token1;

    Pairs.Pair private pair;

    constructor(
        address _superSignature,
        address _token0,
        address _token1,
        int24 strikeInitial
    )
        Positions(_superSignature)
    {
        token0 = _token0;
        token1 = _token1;
        pair.initialize(strikeInitial);
    }

    function addLiquidity(
        int24 strike,
        uint8 spread,
        uint256 balance
    )
        public
        returns (uint256 amount0, uint256 amount1)
    {
        (, amount0, amount1) = pair.provisionLiquidity(strike, spread, int256(balance));

        _mint(
            msg.sender,
            // solhint-disable-next-line max-line-length
            dataID(abi.encode(Positions.ILRTADataID(token0, token1, Positions.OrderType.BiDirectional, strike, spread))),
            balance
        );

        address[] memory tokens = new address[](2);
        tokens[0] = token0;
        tokens[1] = token1;

        int256[] memory tokenDeltas = new int256[](2);
        tokenDeltas[0] = int256(amount0);
        tokenDeltas[1] = int256(amount1);

        uint256 balance0Before = BalanceLib.getBalance(token0);
        uint256 balance1Before = BalanceLib.getBalance(token1);

        IExecuteCallback(msg.sender).executeCallback(tokens, tokenDeltas, new bytes32[](0), new uint256[](0), bytes(""));

        if (BalanceLib.getBalance(token0) < balance0Before + amount0) revert();
        if (BalanceLib.getBalance(token1) < balance1Before + amount1) revert();
    }

    function removeLiquidity(
        int24 strike,
        uint8 spread,
        uint256 balance
    )
        public
        returns (uint256 amount0, uint256 amount1)
    {
        (, amount0, amount1) = pair.provisionLiquidity(strike, spread, -int256(balance));

        SafeTransferLib.safeTransfer(token0, msg.sender, amount0);
        SafeTransferLib.safeTransfer(token1, msg.sender, amount1);

        _burn(
            msg.sender,
            // solhint-disable-next-line max-line-length
            dataID(abi.encode(Positions.ILRTADataID(token0, token1, Positions.OrderType.BiDirectional, strike, spread))),
            balance
        );
    }

    function swap(bool isToken0, int256 amountDesired) public returns (int256 amount0, int256 amount1) {
        (amount0, amount1) = pair.swap(isToken0, amountDesired);

        address[] memory tokens = new address[](2);
        tokens[0] = token0;
        tokens[1] = token1;

        int256[] memory tokenDeltas = new int256[](2);
        tokenDeltas[0] = amount0;
        tokenDeltas[1] = amount1;

        if (isToken0 == (amountDesired > 0)) {
            if (amount1 < 0) SafeTransferLib.safeTransfer(token1, msg.sender, uint256(-amount1));
            uint256 balance0Before = BalanceLib.getBalance(token0);
            IExecuteCallback(msg.sender).executeCallback(
                tokens, tokenDeltas, new bytes32[](0), new uint256[](0), bytes("")
            );
            if (BalanceLib.getBalance(token0) < balance0Before + uint256(amount0)) revert();
        } else {
            if (amount0 < 0) SafeTransferLib.safeTransfer(token0, msg.sender, uint256(-amount0));
            uint256 balance1Before = BalanceLib.getBalance(token1);
            IExecuteCallback(msg.sender).executeCallback(
                tokens, tokenDeltas, new bytes32[](0), new uint256[](0), bytes("")
            );
            if (BalanceLib.getBalance(token1) < balance1Before + uint256(amount1)) revert();
        }
    }

    function getPair()
        external
        view
        returns (
            uint128[NUM_SPREADS] memory composition,
            int24[NUM_SPREADS] memory strikeCurrent,
            int24 cachedStrikeCurrent,
            uint8 initialized
        )
    {
        (composition, strikeCurrent, cachedStrikeCurrent, initialized) =
            (pair.composition, pair.strikeCurrent, pair.cachedStrikeCurrent, pair.initialized);
    }

    function getStrike(int24 strike) external view returns (Pairs.Strike memory) {
        return pair.strikes[strike];
    }

    function getPosition(
        address owner,
        int24 strike,
        uint8 spread
    )
        external
        view
        returns (Positions.ILRTAData memory)
    {
        return _dataOf[owner][dataID(
            abi.encode(Positions.ILRTADataID(token0, token1, Positions.OrderType.BiDirectional, strike, spread))
        )];
    }
}
