// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20 } from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { Ownable } from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import { IDexSwapAdapter } from "../interfaces/IDexSwapAdapter.sol";
import { LibErrors } from "../libs/LibErrors.sol";

interface IWETH {
    function deposit() external payable;
    function withdraw(uint256) external;
    function balanceOf(address) external view returns (uint256);
    function transfer(address, uint256) external returns (bool);
}

contract DummyDexAdapter is IDexSwapAdapter, Ownable {
    using SafeERC20 for IERC20;

    address public immutable wrappedNativeToken;
    address public immutable usdcToken;

    uint256 public reserveWETH;
    uint256 public reserveUSDC;

    event LiquidityAdded(uint256 wethAmount, uint256 usdcAmount);
    event LiquidityRemoved(uint256 wethAmount, uint256 usdcAmount);
    event Swap(address indexed tokenIn, uint256 amountIn, uint256 amountOut);

    error InvalidAddress();
    error InsufficientLiquidity();
    error InsufficientOutputAmount();
    error InvalidToken();
    error InvalidAmount();

    constructor(address _wrappedNativeToken, address _usdcToken, address _owner) {
        if (_wrappedNativeToken == address(0) || _usdcToken == address(0)) {
            revert InvalidAddress();
        }
        if (_owner == address(0)) {
            revert InvalidAddress();
        }

        wrappedNativeToken = _wrappedNativeToken;
        usdcToken = _usdcToken;

        _transferOwnership(_owner);
    }

    function getQuote(
        address tokenIn,
        uint256 amountIn,
        bytes calldata
    ) external payable override {
        bool isNative = tokenIn == address(0);
        bool isWethToUsdc;

        if (isNative) {
            amountIn = msg.value > 0 ? msg.value : amountIn;
            isWethToUsdc = true;
        } else if (tokenIn == wrappedNativeToken) {
            isWethToUsdc = true;
        } else if (tokenIn == usdcToken) {
            isWethToUsdc = false;
        } else {
            revert InvalidToken();
        }

        uint256 amountOut;
        if (isWethToUsdc) {
            if (reserveWETH == 0 || reserveUSDC == 0) revert InsufficientLiquidity();
            amountOut = (amountIn * reserveUSDC) / (reserveWETH + amountIn);
            if (amountOut > reserveUSDC) revert InsufficientLiquidity();
        } else {
            if (reserveWETH == 0 || reserveUSDC == 0) revert InsufficientLiquidity();
            amountOut = (amountIn * reserveWETH) / (reserveUSDC + amountIn);
            if (amountOut > reserveWETH) revert InsufficientLiquidity();
        }

        revert LibErrors.CalculatedAmountOut(amountOut);
    }

    function swap(
        address tokenIn,
        uint256 amountIn,
        uint256 amountOutMinimum,
        bytes calldata
    ) external payable override returns (uint256 amountOut) {
        bool isNative = tokenIn == address(0);
        bool isWethToUsdc;

        if (isNative) {
            IWETH(wrappedNativeToken).deposit{ value: msg.value }();
            isWethToUsdc = true;
        } else if (tokenIn == wrappedNativeToken) {
            IERC20(wrappedNativeToken).safeTransferFrom(msg.sender, address(this), amountIn);
            isWethToUsdc = true;
        } else if (tokenIn == usdcToken) {
            IERC20(usdcToken).safeTransferFrom(msg.sender, address(this), amountIn);
            isWethToUsdc = false;
        } else {
            revert InvalidToken();
        }

        if (isWethToUsdc) {
            if (reserveWETH == 0 || reserveUSDC == 0) revert InsufficientLiquidity();

            amountOut = (amountIn * reserveUSDC) / (reserveWETH + amountIn);

            if (amountOut < amountOutMinimum) revert InsufficientOutputAmount();
            if (amountOut > reserveUSDC) revert InsufficientLiquidity();

            reserveWETH += amountIn;
            reserveUSDC -= amountOut;

            IERC20(usdcToken).safeTransfer(msg.sender, amountOut);
        } else {
            if (reserveWETH == 0 || reserveUSDC == 0) revert InsufficientLiquidity();

            amountOut = (amountIn * reserveWETH) / (reserveUSDC + amountIn);

            if (amountOut < amountOutMinimum) revert InsufficientOutputAmount();
            if (amountOut > reserveWETH) revert InsufficientLiquidity();

            reserveUSDC += amountIn;
            reserveWETH -= amountOut;

            IERC20(wrappedNativeToken).safeTransfer(msg.sender, amountOut);
        }

        emit Swap(tokenIn, amountIn, amountOut);
        return amountOut;
    }

    function addLiquidity(uint256 wethAmount, uint256 usdcAmount) external onlyOwner {
        if (wethAmount == 0 || usdcAmount == 0) revert InvalidAmount();

        IERC20(wrappedNativeToken).safeTransferFrom(msg.sender, address(this), wethAmount);
        IERC20(usdcToken).safeTransferFrom(msg.sender, address(this), usdcAmount);

        reserveWETH += wethAmount;
        reserveUSDC += usdcAmount;

        emit LiquidityAdded(wethAmount, usdcAmount);
    }

    function removeLiquidity(uint256 wethAmount, uint256 usdcAmount) external onlyOwner {
        if (wethAmount > reserveWETH || usdcAmount > reserveUSDC) {
            revert InsufficientLiquidity();
        }

        reserveWETH -= wethAmount;
        reserveUSDC -= usdcAmount;

        if (wethAmount > 0) {
            IERC20(wrappedNativeToken).safeTransfer(msg.sender, wethAmount);
        }
        if (usdcAmount > 0) {
            IERC20(usdcToken).safeTransfer(msg.sender, usdcAmount);
        }

        emit LiquidityRemoved(wethAmount, usdcAmount);
    }

    receive() external payable {
        revert("Use swap() for native token swaps");
    }
}
