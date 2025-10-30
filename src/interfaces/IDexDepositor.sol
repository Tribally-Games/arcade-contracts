// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IDexDepositor {
    /// @notice Get quote for swapping tokens to USDC
    /// @dev Reverts with CalculatedAmountOut(uint256) containing the expected USDC output amount
    /// @param tokenIn Input token address (ERC20 tokens only, address(0) for native token)
    /// @param amountIn Exact input amount
    /// @param path Encoded swap path (format depends on DEX implementation)
    function getQuote(
        address tokenIn,
        uint256 amountIn,
        bytes calldata path
    ) external payable;

    /// @notice Swap tokens to USDC and deposit to diamond on behalf of user
    /// @param user User address to deposit for
    /// @param tokenIn Input token address (ERC20 tokens only, address(0) for native token)
    /// @param amountIn Exact input amount
    /// @param amountOutMinimum Minimum USDC output amount to receive (slippage protection)
    /// @param path Encoded swap path (format depends on DEX implementation)
    /// @return usdcAmount Actual USDC amount deposited to diamond
    function deposit(
        address user,
        address tokenIn,
        uint256 amountIn,
        uint256 amountOutMinimum,
        bytes calldata path
    ) external payable returns (uint256 usdcAmount);
}
