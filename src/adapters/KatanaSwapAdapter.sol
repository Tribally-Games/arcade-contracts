// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20 } from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { IDexSwapAdapter } from "../interfaces/IDexSwapAdapter.sol";
import { IKatanaRouter } from "../interfaces/IKatanaRouter.sol";

contract KatanaSwapAdapter is IDexSwapAdapter {
    using SafeERC20 for IERC20;

    address public immutable katanaRouter;
    address public immutable override usdcToken;
    address public owner;

    bytes1 private constant V3_SWAP_EXACT_IN = 0x00;

    event RouterUpdated(address indexed oldRouter, address indexed newRouter);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event TokensRescued(address indexed token, address indexed to, uint256 amount);

    error OnlyOwner();
    error InvalidAddress();

    modifier onlyOwner() {
        if (msg.sender != owner) revert OnlyOwner();
        _;
    }

    constructor(address _katanaRouter, address _usdcToken, address _owner) {
        if (_katanaRouter == address(0) || _usdcToken == address(0) || _owner == address(0)) {
            revert InvalidAddress();
        }

        katanaRouter = _katanaRouter;
        usdcToken = _usdcToken;
        owner = _owner;
    }

    function swap(
        address tokenIn,
        uint256 amountIn,
        uint256 amountOutMinimum,
        bytes calldata path
    ) external override returns (uint256 amountOut) {
        uint256 usdcBalanceBefore = IERC20(usdcToken).balanceOf(address(this));

        IERC20(tokenIn).safeApprove(katanaRouter, amountIn);

        bytes memory commands = abi.encodePacked(V3_SWAP_EXACT_IN);
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(
            address(this),
            amountIn,
            amountOutMinimum,
            false,
            path
        );

        IKatanaRouter(katanaRouter).execute(commands, inputs, block.timestamp + 300);

        uint256 usdcBalanceAfter = IERC20(usdcToken).balanceOf(address(this));
        amountOut = usdcBalanceAfter - usdcBalanceBefore;

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
