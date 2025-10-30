// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20 } from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { Ownable } from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import { IDexDepositor } from "../interfaces/IDexDepositor.sol";
import { IGatewayFacet } from "../interfaces/IGatewayFacet.sol";
import { LibErrors } from "../libs/LibErrors.sol";

interface IWETH {
    function deposit() external payable;
    function withdraw(uint256) external;
    function balanceOf(address) external view returns (uint256);
    function transfer(address, uint256) external returns (bool);
}

contract DummyDexDepositor is IDexDepositor, Ownable {
    using SafeERC20 for IERC20;

    address public immutable wrappedNativeToken;
    address public immutable diamondProxy;
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

    constructor(
        address _wrappedNativeToken,
        address _diamondProxy,
        address _usdcToken,
        address _owner
    ) {
        if (_wrappedNativeToken == address(0)) revert InvalidAddress();
        if (_diamondProxy == address(0)) revert InvalidAddress();
        if (_usdcToken == address(0)) revert InvalidAddress();
        if (_owner == address(0)) revert InvalidAddress();

        wrappedNativeToken = _wrappedNativeToken;
        diamondProxy = _diamondProxy;
        usdcToken = _usdcToken;

        _transferOwnership(_owner);
    }

    function getQuote(
        address tokenIn,
        uint256 amountIn,
        bytes calldata
    ) external payable override {
        if (tokenIn == usdcToken) {
            revert LibErrors.CalculatedAmountOut(amountIn);
        }

        bool isNative = tokenIn == address(0);

        if (isNative) {
            amountIn = msg.value > 0 ? msg.value : amountIn;
        } else if (tokenIn != wrappedNativeToken) {
            revert InvalidToken();
        }

        if (reserveWETH == 0 || reserveUSDC == 0) revert InsufficientLiquidity();
        uint256 usdcAmount = (amountIn * reserveUSDC) / (reserveWETH + amountIn);
        if (usdcAmount > reserveUSDC) revert InsufficientLiquidity();

        revert LibErrors.CalculatedAmountOut(usdcAmount);
    }

    function deposit(
        address user,
        address tokenIn,
        uint256 amountIn,
        uint256 amountOutMinimum,
        bytes calldata
    ) external payable override returns (uint256 usdcAmount) {
        if (tokenIn == usdcToken) {
            IERC20(usdcToken).safeTransferFrom(msg.sender, address(this), amountIn);
            usdcAmount = amountIn;
        } else {
            usdcAmount = _performSwap(tokenIn, amountIn, amountOutMinimum);
        }

        IERC20(usdcToken).forceApprove(diamondProxy, usdcAmount);
        IGatewayFacet(diamondProxy).deposit(user, usdcAmount);
        IERC20(usdcToken).forceApprove(diamondProxy, 0);

        emit Swap(tokenIn, amountIn, usdcAmount);
        return usdcAmount;
    }

    function _performSwap(
        address tokenIn,
        uint256 amountIn,
        uint256 amountOutMinimum
    ) private returns (uint256 usdcAmount) {
        bool isNative = tokenIn == address(0);

        if (isNative) {
            IWETH(wrappedNativeToken).deposit{ value: msg.value }();
        } else if (tokenIn == wrappedNativeToken) {
            IERC20(wrappedNativeToken).safeTransferFrom(msg.sender, address(this), amountIn);
        } else {
            revert InvalidToken();
        }

        if (reserveWETH == 0 || reserveUSDC == 0) revert InsufficientLiquidity();

        usdcAmount = (amountIn * reserveUSDC) / (reserveWETH + amountIn);

        if (usdcAmount < amountOutMinimum) revert InsufficientOutputAmount();
        if (usdcAmount > reserveUSDC) revert InsufficientLiquidity();

        reserveWETH += amountIn;
        reserveUSDC -= usdcAmount;

        return usdcAmount;
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
        revert("Use deposit() for native token deposits");
    }
}
