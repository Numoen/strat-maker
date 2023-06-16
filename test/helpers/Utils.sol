// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import {Engine} from "src/core/Engine.sol";
import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";
import "forge-std/Vm.sol";

function createCommand(
    address token0,
    address token1,
    int24 tickInitial
)
    pure
    returns (Engine.Commands command, bytes memory input)
{
    return (Engine.Commands.CreatePair, abi.encode(Engine.CreatePairParams(token0, token1, tickInitial)));
}

function addLiquidityCommand(
    address token0,
    address token1,
    int24 strike,
    uint8 spread,
    Engine.TokenSelector selector,
    int256 amountDesired
)
    pure
    returns (Engine.Commands command, bytes memory input)
{
    return (
        Engine.Commands.AddLiquidity,
        abi.encode(Engine.AddLiquidityParams(token0, token1, strike, spread, selector, amountDesired))
    );
}

function removeLiquidityCommand(
    address token0,
    address token1,
    int24 strike,
    uint8 spread,
    Engine.TokenSelector selector,
    int256 amountDesired
)
    pure
    returns (Engine.Commands command, bytes memory input)
{
    return (
        Engine.Commands.RemoveLiquidity,
        abi.encode(Engine.RemoveLiquidityParams(token0, token1, strike, spread, selector, amountDesired))
    );
}

function swapCommand(
    address token0,
    address token1,
    Engine.TokenSelector selector,
    int256 amountDesired
)
    pure
    returns (Engine.Commands command, bytes memory input)
{
    return (Engine.Commands.Swap, abi.encode(Engine.SwapParams(token0, token1, selector, amountDesired)));
}

function createCommands() pure returns (Engine.Commands[] memory commands) {
    return new Engine.Commands[](0);
}

function createInputs() pure returns (bytes[] memory inputs) {
    return new bytes[](0);
}

function pushCommands(
    Engine.Commands[] memory commands,
    Engine.Commands command
)
    pure
    returns (Engine.Commands[] memory)
{
    Engine.Commands[] memory newCommands = new Engine.Commands[](commands.length +1);

    for (uint256 i = 0; i < commands.length; i++) {
        newCommands[i] = commands[i];
    }

    newCommands[commands.length] = command;

    return newCommands;
}

function pushInputs(bytes[] memory inputs, bytes memory input) pure returns (bytes[] memory) {
    bytes[] memory newInputs = new bytes[](inputs.length + 1);

    for (uint256 i = 0; i < inputs.length; i++) {
        newInputs[i] = inputs[i];
    }

    newInputs[inputs.length] = input;

    return newInputs;
}
