// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IQuoterV2 } from "lib/uniswap-v3-periphery/contracts/interfaces/IQuoterV2.sol";

contract MockQuoterV2 is IQuoterV2 {
    uint256 public constant EXCHANGE_RATE = 2000;

    function quoteExactInput(bytes memory, uint256 amountIn)
        external
        pure
        override
        returns (
            uint256 amountOut,
            uint160[] memory sqrtPriceX96AfterList,
            uint32[] memory initializedTicksCrossedList,
            uint256 gasEstimate
        )
    {
        amountOut = (amountIn * EXCHANGE_RATE) / 1e12;
        sqrtPriceX96AfterList = new uint160[](0);
        initializedTicksCrossedList = new uint32[](0);
        gasEstimate = 100000;
    }

    function quoteExactInputSingle(QuoteExactInputSingleParams memory params)
        external
        pure
        override
        returns (uint256 amountOut, uint160 sqrtPriceX96After, uint32 initializedTicksCrossed, uint256 gasEstimate)
    {
        amountOut = (params.amountIn * EXCHANGE_RATE) / 1e12;
        sqrtPriceX96After = 0;
        initializedTicksCrossed = 0;
        gasEstimate = 100000;
    }

    function quoteExactOutput(bytes memory, uint256 amountOut)
        external
        pure
        override
        returns (
            uint256 amountIn,
            uint160[] memory sqrtPriceX96AfterList,
            uint32[] memory initializedTicksCrossedList,
            uint256 gasEstimate
        )
    {
        amountIn = (amountOut * 1e12) / EXCHANGE_RATE;
        sqrtPriceX96AfterList = new uint160[](0);
        initializedTicksCrossedList = new uint32[](0);
        gasEstimate = 100000;
    }

    function quoteExactOutputSingle(QuoteExactOutputSingleParams memory params)
        external
        pure
        override
        returns (uint256 amountIn, uint160 sqrtPriceX96After, uint32 initializedTicksCrossed, uint256 gasEstimate)
    {
        amountIn = (params.amount * 1e12) / EXCHANGE_RATE;
        sqrtPriceX96After = 0;
        initializedTicksCrossed = 0;
        gasEstimate = 100000;
    }
}
