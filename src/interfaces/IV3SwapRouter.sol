// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IV3SwapRouter {
    struct ExactInputParams {
        bytes path;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
    }

    /// @notice Swap with exact input amount
    /// @param params Swap parameters
    /// @return amountOut Amount of output token received
    function exactInput(ExactInputParams calldata params)
        external
        payable
        returns (uint256 amountOut);
}
