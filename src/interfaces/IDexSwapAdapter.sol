// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IDexSwapAdapter {
    /// @notice Get quote for swapping tokens
    /// @dev Reverts with CalculatedAmountOut(uint256) containing the expected output amount.
    /// @param tokenIn Input token address (ERC20 tokens only, address(0) for native token)
    /// @param amountIn Exact input amount
    /// @param path Encoded swap path (format depends on DEX implementation)
    function getQuote(
        address tokenIn,
        uint256 amountIn,
        bytes calldata path
    ) external payable;

    /// @notice Swap tokens using DEX-specific routing
    /// @param tokenIn Input token address (ERC20 tokens only, address(0) for native token)
    /// @param amountIn Exact input amount
    /// @param amountOutMinimum Minimum output amount to receive (slippage protection)
    /// @param path Encoded swap path (format depends on DEX implementation)
    /// @return amountOut Actual output amount received
    function swap(
        address tokenIn,
        uint256 amountIn,
        uint256 amountOutMinimum,
        bytes calldata path
    ) external payable returns (uint256 amountOut);
}
