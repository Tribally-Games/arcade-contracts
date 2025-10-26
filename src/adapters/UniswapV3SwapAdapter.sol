// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20 } from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { IDexSwapAdapter } from "../interfaces/IDexSwapAdapter.sol";
import { IV3SwapRouter } from "../interfaces/IV3SwapRouter.sol";
import { IQuoterV2 } from "lib/uniswap-v3-periphery/contracts/interfaces/IQuoterV2.sol";

contract UniswapV3SwapAdapter is IDexSwapAdapter {
    using SafeERC20 for IERC20;

    address public immutable swapRouter;
    address public immutable quoterV2;
    address public owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event TokensRescued(address indexed token, address indexed to, uint256 amount);

    error OnlyOwner();
    error InvalidAddress();

    modifier onlyOwner() {
        if (msg.sender != owner) revert OnlyOwner();
        _;
    }

    constructor(address _swapRouter, address _quoterV2) {
        if (_swapRouter == address(0) || _quoterV2 == address(0)) revert InvalidAddress();

        swapRouter = _swapRouter;
        quoterV2 = _quoterV2;
        owner = msg.sender;
    }

    function getQuote(
        address tokenIn,
        uint256 amountIn,
        bytes calldata path
    ) external payable override returns (uint256 amountOut) {
        (amountOut,,,) = IQuoterV2(quoterV2).quoteExactInput(path, amountIn);
        return amountOut;
    }

    function swap(
        address tokenIn,
        uint256 amountIn,
        uint256 amountOutMinimum,
        bytes calldata path
    ) external payable override returns (uint256 amountOut) {
        bool isNative = tokenIn == address(0);

        IV3SwapRouter.ExactInputParams memory params = IV3SwapRouter.ExactInputParams({
            path: path,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: amountIn,
            amountOutMinimum: amountOutMinimum
        });

        if (isNative) {
            amountOut = IV3SwapRouter(swapRouter).exactInput{ value: msg.value }(params);
        } else {
            IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
            IERC20(tokenIn).forceApprove(swapRouter, amountIn);
            amountOut = IV3SwapRouter(swapRouter).exactInput(params);
        }

        address tokenOut = _extractOutputToken(path);
        IERC20(tokenOut).safeTransfer(msg.sender, amountOut);

        return amountOut;
    }

    function _extractOutputToken(bytes calldata path) private pure returns (address tokenOut) {
        assembly {
            tokenOut := shr(96, calldataload(add(path.offset, sub(path.length, 20))))
        }
    }

    function rescueTokens(address _token, uint256 _amount) external onlyOwner {
        if (_token == address(0)) {
            (bool success, ) = owner.call{value: _amount}("");
            require(success, "ETH transfer failed");
        } else {
            IERC20(_token).safeTransfer(owner, _amount);
        }

        emit TokensRescued(_token, owner, _amount);
    }

    function transferOwnership(address _newOwner) external onlyOwner {
        if (_newOwner == address(0)) revert InvalidAddress();

        address oldOwner = owner;
        owner = _newOwner;

        emit OwnershipTransferred(oldOwner, _newOwner);
    }

    receive() external payable {}
}
