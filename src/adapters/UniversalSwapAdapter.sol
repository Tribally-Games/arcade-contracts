// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20 } from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { Ownable } from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import { ReentrancyGuard } from "lib/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import { IDexSwapAdapter } from "../interfaces/IDexSwapAdapter.sol";
import { IUniversalRouter } from "../interfaces/IUniversalRouter.sol";
import { Commands } from "lib/katana-operation-contracts/src/aggregate-router/libraries/Commands.sol";

contract UniversalSwapAdapter is IDexSwapAdapter, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public immutable universalRouter;

    address private constant ADDRESS_THIS = address(2);

    uint256 public swapDeadline = 300;

    event TokensRescued(address indexed token, address indexed to, uint256 amount);
    event SwapDeadlineUpdated(uint256 oldDeadline, uint256 newDeadline);

    error InvalidAddress();
    error InvalidDeadline();

    constructor(address _universalRouter, address _owner) {
        if (_universalRouter == address(0)) revert InvalidAddress();
        if (_owner == address(0)) revert InvalidAddress();

        universalRouter = _universalRouter;

        _transferOwnership(_owner);
    }

    function getQuote(
        address tokenIn,
        uint256 amountIn,
        bytes calldata path
    ) external payable override returns (uint256 amountOut) {
        return this.swap{ value: msg.value }(tokenIn, amountIn, 0, path);
    }

    function swap(
        address tokenIn,
        uint256 amountIn,
        uint256 amountOutMinimum,
        bytes calldata path
    ) external payable override nonReentrant returns (uint256 amountOut) {
        address tokenOut = _extractOutputToken(path);
        uint256 balanceBefore = IERC20(tokenOut).balanceOf(address(this));

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

            IUniversalRouter(universalRouter).execute{ value: msg.value }(
                commands,
                inputs,
                block.timestamp + swapDeadline
            );
        } else {
            IERC20(tokenIn).safeTransferFrom(msg.sender, universalRouter, amountIn);

            bytes memory commands = abi.encodePacked(bytes1(uint8(Commands.V3_SWAP_EXACT_IN)));
            bytes[] memory inputs = new bytes[](1);

            inputs[0] = abi.encode(
                address(this),
                amountIn,
                amountOutMinimum,
                path,
                false
            );

            IUniversalRouter(universalRouter).execute(commands, inputs, block.timestamp + swapDeadline);
        }

        uint256 balanceAfter = IERC20(tokenOut).balanceOf(address(this));
        amountOut = balanceAfter - balanceBefore;

        IERC20(tokenOut).safeTransfer(msg.sender, amountOut);

        return amountOut;
    }

    function _extractOutputToken(bytes calldata path) private pure returns (address tokenOut) {
        assembly {
            tokenOut := shr(96, calldataload(add(path.offset, sub(path.length, 20))))
        }
    }

    function setSwapDeadline(uint256 _deadline) external onlyOwner {
        if (_deadline == 0) revert InvalidDeadline();

        uint256 oldDeadline = swapDeadline;
        swapDeadline = _deadline;

        emit SwapDeadlineUpdated(oldDeadline, _deadline);
    }

    function rescueTokens(address _token, uint256 _amount) external onlyOwner {
        if (_token == address(0)) revert InvalidAddress();

        IERC20(_token).safeTransfer(owner(), _amount);

        emit TokensRescued(_token, owner(), _amount);
    }
}
