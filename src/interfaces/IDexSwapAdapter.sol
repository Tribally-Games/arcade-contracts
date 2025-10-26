// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IDexSwapAdapter {
    /// @notice Swap tokens to USDC
    /// @dev Frontend can call via eth_call for quotes without execution
    /// @param tokenIn Input token address (address(0) for native token)
    /// @param amountIn Exact input amount
    /// @param amountOutMinimum Minimum USDC to receive (slippage protection)
    /// @param path Encoded swap path
    /// @return amountOut Actual USDC received (or simulated if called via eth_call)
    function swap(
        address tokenIn,
        uint256 amountIn,
        uint256 amountOutMinimum,
        bytes calldata path
    ) external payable returns (uint256 amountOut);
}
