// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20 } from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { Ownable } from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import { IDexSwapAdapter } from "../interfaces/IDexSwapAdapter.sol";
import { IKatanaRouter } from "../interfaces/IKatanaRouter.sol";
import { Commands } from "lib/katana-operation-contracts/src/aggregate-router/libraries/Commands.sol";

contract KatanaSwapAdapter is IDexSwapAdapter, Ownable {
    using SafeERC20 for IERC20;

    address public immutable katanaRouter;
    address public immutable override usdcToken;

    address private constant ADDRESS_THIS = address(2);

    event TokensRescued(address indexed token, address indexed to, uint256 amount);

    error InvalidAddress();

    constructor(address _katanaRouter, address _usdcToken, address _owner) {
        if (_katanaRouter == address(0) || _usdcToken == address(0) || _owner == address(0)) {
            revert InvalidAddress();
        }

        katanaRouter = _katanaRouter;
        usdcToken = _usdcToken;

        _transferOwnership(_owner);
    }

    function swap(
        address tokenIn,
        uint256 amountIn,
        uint256 amountOutMinimum,
        bytes calldata path
    ) external payable override returns (uint256 amountOut) {
        uint256 usdcBalanceBefore = IERC20(usdcToken).balanceOf(address(this));

        bool isNative = tokenIn == address(0);

        if (isNative) {
            bytes memory commands = abi.encodePacked(
                bytes1(uint8(Commands.WRAP_ETH)),
                bytes1(uint8(Commands.V3_SWAP_EXACT_IN))
            );
            bytes[] memory inputs = new bytes[](2);

            inputs[0] = abi.encode(ADDRESS_THIS, amountIn);

            inputs[1] = abi.encode(
                address(this),
                amountIn,
                amountOutMinimum,
                path,
                false
            );

            IKatanaRouter(katanaRouter).execute{ value: msg.value }(
                commands,
                inputs,
                block.timestamp + 300
            );
        } else {
            IERC20(tokenIn).safeTransferFrom(msg.sender, katanaRouter, amountIn);

            bytes memory commands = abi.encodePacked(bytes1(uint8(Commands.V3_SWAP_EXACT_IN)));
            bytes[] memory inputs = new bytes[](1);

            inputs[0] = abi.encode(
                address(this),
                amountIn,
                amountOutMinimum,
                path,
                false
            );

            IKatanaRouter(katanaRouter).execute(commands, inputs, block.timestamp + 300);
        }

        uint256 usdcBalanceAfter = IERC20(usdcToken).balanceOf(address(this));
        amountOut = usdcBalanceAfter - usdcBalanceBefore;

        IERC20(usdcToken).safeTransfer(msg.sender, amountOut);

        return amountOut;
    }

    function rescueTokens(address _token, uint256 _amount) external onlyOwner {
        if (_token == address(0)) revert InvalidAddress();

        IERC20(_token).safeTransfer(owner(), _amount);

        emit TokensRescued(_token, owner(), _amount);
    }
}
