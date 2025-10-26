// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20 } from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { IDexSwapAdapter } from "../interfaces/IDexSwapAdapter.sol";
import { IV3SwapRouter } from "../interfaces/IV3SwapRouter.sol";

contract UniswapV3SwapAdapter is IDexSwapAdapter {
    using SafeERC20 for IERC20;

    address public immutable swapRouter;
    address private immutable usdcToken;
    address public owner;

    event RouterUpdated(address indexed oldRouter, address indexed newRouter);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event TokensRescued(address indexed token, address indexed to, uint256 amount);

    error OnlyOwner();
    error InvalidAddress();

    modifier onlyOwner() {
        if (msg.sender != owner) revert OnlyOwner();
        _;
    }

    constructor(address _swapRouter, address _usdcToken, address _owner) {
        if (_swapRouter == address(0) || _usdcToken == address(0) || _owner == address(0)) {
            revert InvalidAddress();
        }

        swapRouter = _swapRouter;
        usdcToken = _usdcToken;
        owner = _owner;
    }

    function swap(
        address tokenIn,
        uint256 amountIn,
        uint256 amountOutMinimum,
        bytes calldata path
    ) external payable override returns (uint256 amountOut) {
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        IERC20(tokenIn).forceApprove(swapRouter, amountIn);

        IV3SwapRouter.ExactInputParams memory params = IV3SwapRouter.ExactInputParams({
            path: path,
            recipient: address(this),
            amountIn: amountIn,
            amountOutMinimum: amountOutMinimum
        });

        amountOut = IV3SwapRouter(swapRouter).exactInput(params);

        IERC20(usdcToken).safeTransfer(msg.sender, amountOut);

        return amountOut;
    }

    function rescueTokens(address _token, uint256 _amount) external onlyOwner {
        if (_token == address(0)) revert InvalidAddress();

        IERC20(_token).safeTransfer(owner, _amount);

        emit TokensRescued(_token, owner, _amount);
    }

    function transferOwnership(address _newOwner) external onlyOwner {
        if (_newOwner == address(0)) revert InvalidAddress();

        address oldOwner = owner;
        owner = _newOwner;

        emit OwnershipTransferred(oldOwner, _newOwner);
    }
}
