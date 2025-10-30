// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20 } from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { Ownable } from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import { ReentrancyGuard } from "lib/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import { IDexDepositor } from "../interfaces/IDexDepositor.sol";
import { IUniversalRouter } from "../interfaces/IUniversalRouter.sol";
import { IGatewayFacet } from "../interfaces/IGatewayFacet.sol";
import { Commands } from "lib/katana-operation-contracts/src/aggregate-router/libraries/Commands.sol";
import { LibErrors } from "../libs/LibErrors.sol";

contract UniversalDexDepositor is IDexDepositor, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public immutable universalRouter;
    address public immutable diamondProxy;
    address public immutable usdcToken;

    address private constant ADDRESS_THIS = address(2);

    uint256 public swapDeadline = 300;

    event TokensRescued(address indexed token, address indexed to, uint256 amount);
    event SwapDeadlineUpdated(uint256 oldDeadline, uint256 newDeadline);

    error InvalidAddress();
    error InvalidDeadline();

    constructor(
        address _universalRouter,
        address _diamondProxy,
        address _usdcToken,
        address _owner
    ) {
        if (_universalRouter == address(0)) revert InvalidAddress();
        if (_diamondProxy == address(0)) revert InvalidAddress();
        if (_usdcToken == address(0)) revert InvalidAddress();
        if (_owner == address(0)) revert InvalidAddress();

        universalRouter = _universalRouter;
        diamondProxy = _diamondProxy;
        usdcToken = _usdcToken;

        _transferOwnership(_owner);
    }

    function getQuote(
        address tokenIn,
        uint256 amountIn,
        bytes calldata path
    ) external payable override {
        uint256 usdcAmount;

        if (tokenIn == usdcToken) {
            usdcAmount = amountIn;
        } else {
            usdcAmount = _performSwap(tokenIn, amountIn, 0, path);
        }

        revert LibErrors.CalculatedAmountOut(usdcAmount);
    }

    function deposit(
        address user,
        address tokenIn,
        uint256 amountIn,
        uint256 amountOutMinimum,
        bytes calldata path
    ) external payable override nonReentrant returns (uint256 usdcAmount) {
        bool isNative = tokenIn == address(0);
        bool isUsdc = tokenIn == usdcToken;

        if (isUsdc) {
            IERC20(usdcToken).safeTransferFrom(msg.sender, address(this), amountIn);
            usdcAmount = amountIn;
        } else {
            usdcAmount = _performSwap(tokenIn, amountIn, amountOutMinimum, path);
        }

        IERC20(usdcToken).forceApprove(diamondProxy, usdcAmount);
        IGatewayFacet(diamondProxy).deposit(user, usdcAmount);
        IERC20(usdcToken).forceApprove(diamondProxy, 0);

        return usdcAmount;
    }

    function _performSwap(
        address tokenIn,
        uint256 amountIn,
        uint256 amountOutMinimum,
        bytes calldata path
    ) private returns (uint256 usdcAmount) {
        uint256 balanceBefore = IERC20(usdcToken).balanceOf(address(this));

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

        uint256 balanceAfter = IERC20(usdcToken).balanceOf(address(this));
        usdcAmount = balanceAfter - balanceBefore;

        return usdcAmount;
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

    receive() external payable {
        revert("Use deposit() for native token deposits");
    }
}
