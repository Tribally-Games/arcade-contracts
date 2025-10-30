// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import { DummyDexDepositor } from "src/depositors/DummyDexDepositor.sol";
import { MockDiamond } from "./mocks/MockDiamond.sol";
import { MockWETH } from "src/mocks/MockWETH.sol";
import { TestERC20 } from "src/mocks/TestERC20.sol";
import { IERC20 } from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { LibErrors } from "src/libs/LibErrors.sol";

contract DummyDexDepositorTest is Test {
    DummyDexDepositor public depositor;
    MockDiamond public diamond;
    MockWETH public weth;
    TestERC20 public usdc;

    address public owner = address(this);
    address public user = address(0x1234);
    address public nonOwner = address(0x5678);

    uint256 public constant INITIAL_WETH_LIQUIDITY = 100 ether;
    uint256 public constant INITIAL_USDC_LIQUIDITY = 200_000e6;

    event LiquidityAdded(uint256 wethAmount, uint256 usdcAmount);
    event LiquidityRemoved(uint256 wethAmount, uint256 usdcAmount);
    event Swap(address indexed tokenIn, uint256 amountIn, uint256 amountOut);

    function setUp() public {
        weth = new MockWETH();
        usdc = new TestERC20("USD Coin", "USDC", 6);
        diamond = new MockDiamond(address(usdc));

        vm.prank(owner);
        depositor = new DummyDexDepositor(address(weth), address(diamond), address(usdc), owner);

        usdc.mint(owner, INITIAL_USDC_LIQUIDITY * 2);
        weth.deposit{ value: INITIAL_WETH_LIQUIDITY * 2 }();

        weth.approve(address(depositor), type(uint256).max);
        usdc.approve(address(depositor), type(uint256).max);

        depositor.addLiquidity(INITIAL_WETH_LIQUIDITY, INITIAL_USDC_LIQUIDITY);

        vm.deal(user, 1000 ether);
        weth.deposit{ value: 100 ether }();
        weth.transfer(user, 100 ether);
        usdc.mint(user, 100_000e6);

        vm.label(owner, "Owner");
        vm.label(user, "User");
        vm.label(nonOwner, "NonOwner");
    }

    function test_Constructor_RevertsWhenWethIsZeroAddress() public {
        vm.expectRevert(DummyDexDepositor.InvalidAddress.selector);
        new DummyDexDepositor(address(0), address(diamond), address(usdc), owner);
    }

    function test_Constructor_RevertsWhenDiamondIsZeroAddress() public {
        vm.expectRevert(DummyDexDepositor.InvalidAddress.selector);
        new DummyDexDepositor(address(weth), address(0), address(usdc), owner);
    }

    function test_Constructor_RevertsWhenUsdcIsZeroAddress() public {
        vm.expectRevert(DummyDexDepositor.InvalidAddress.selector);
        new DummyDexDepositor(address(weth), address(diamond), address(0), owner);
    }

    function test_Constructor_RevertsWhenOwnerIsZeroAddress() public {
        vm.expectRevert(DummyDexDepositor.InvalidAddress.selector);
        new DummyDexDepositor(address(weth), address(diamond), address(usdc), address(0));
    }

    function test_Constructor_SetsCorrectAddresses() public view {
        assertEq(depositor.wrappedNativeToken(), address(weth));
        assertEq(depositor.diamondProxy(), address(diamond));
        assertEq(depositor.usdcToken(), address(usdc));
        assertEq(depositor.owner(), owner);
    }

    function test_Constructor_SetsDeployerAsOwner() public {
        address deployer = address(0x1111);
        vm.prank(deployer);
        DummyDexDepositor newDepositor = new DummyDexDepositor(address(weth), address(diamond), address(usdc), deployer);
        assertEq(newDepositor.owner(), deployer);
    }

    function test_AddLiquidity_RevertsWhenNotOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert();
        depositor.addLiquidity(1 ether, 2000e6);
    }

    function test_AddLiquidity_RevertsWhenWethAmountIsZero() public {
        vm.expectRevert(DummyDexDepositor.InvalidAmount.selector);
        depositor.addLiquidity(0, 2000e6);
    }

    function test_AddLiquidity_RevertsWhenUsdcAmountIsZero() public {
        vm.expectRevert(DummyDexDepositor.InvalidAmount.selector);
        depositor.addLiquidity(1 ether, 0);
    }

    function test_AddLiquidity_UpdatesReserves() public {
        uint256 reserveWethBefore = depositor.reserveWETH();
        uint256 reserveUsdcBefore = depositor.reserveUSDC();

        depositor.addLiquidity(10 ether, 20_000e6);

        assertEq(depositor.reserveWETH(), reserveWethBefore + 10 ether);
        assertEq(depositor.reserveUSDC(), reserveUsdcBefore + 20_000e6);
    }

    function test_AddLiquidity_EmitsEvent() public {
        vm.expectEmit(true, true, false, true);
        emit LiquidityAdded(10 ether, 20_000e6);

        depositor.addLiquidity(10 ether, 20_000e6);
    }

    function test_RemoveLiquidity_RevertsWhenNotOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert();
        depositor.removeLiquidity(1 ether, 2000e6);
    }

    function test_RemoveLiquidity_RevertsWhenInsufficientLiquidity() public {
        vm.expectRevert(DummyDexDepositor.InsufficientLiquidity.selector);
        depositor.removeLiquidity(INITIAL_WETH_LIQUIDITY + 1, 0);
    }

    function test_RemoveLiquidity_UpdatesReserves() public {
        uint256 wethToRemove = 10 ether;
        uint256 usdcToRemove = 20_000e6;

        uint256 reserveWethBefore = depositor.reserveWETH();
        uint256 reserveUsdcBefore = depositor.reserveUSDC();

        depositor.removeLiquidity(wethToRemove, usdcToRemove);

        assertEq(depositor.reserveWETH(), reserveWethBefore - wethToRemove);
        assertEq(depositor.reserveUSDC(), reserveUsdcBefore - usdcToRemove);
    }

    function test_RemoveLiquidity_TransfersTokens() public {
        uint256 wethToRemove = 10 ether;
        uint256 usdcToRemove = 20_000e6;

        uint256 wethBalanceBefore = weth.balanceOf(owner);
        uint256 usdcBalanceBefore = usdc.balanceOf(owner);

        depositor.removeLiquidity(wethToRemove, usdcToRemove);

        assertEq(weth.balanceOf(owner), wethBalanceBefore + wethToRemove);
        assertEq(usdc.balanceOf(owner), usdcBalanceBefore + usdcToRemove);
    }

    function test_RemoveLiquidity_EmitsEvent() public {
        vm.expectEmit(true, true, false, true);
        emit LiquidityRemoved(10 ether, 20_000e6);

        depositor.removeLiquidity(10 ether, 20_000e6);
    }

    function test_Deposit_NativeToken_Success() public {
        uint256 amountIn = 1 ether;
        uint256 expectedUsdc = (amountIn * INITIAL_USDC_LIQUIDITY) / (INITIAL_WETH_LIQUIDITY + amountIn);

        vm.startPrank(user);
        uint256 usdcAmount = depositor.deposit{ value: amountIn }(user, address(0), amountIn, 0, "");
        vm.stopPrank();

        assertGt(usdcAmount, 0);
        assertApproxEqAbs(usdcAmount, expectedUsdc, 1);
        assertEq(diamond.gatewayPoolBalance(), usdcAmount);
    }

    function test_Deposit_WETH_Success() public {
        uint256 amountIn = 1 ether;
        uint256 expectedUsdc = (amountIn * INITIAL_USDC_LIQUIDITY) / (INITIAL_WETH_LIQUIDITY + amountIn);

        vm.startPrank(user);
        weth.approve(address(depositor), amountIn);
        uint256 usdcAmount = depositor.deposit(user, address(weth), amountIn, 0, "");
        vm.stopPrank();

        assertGt(usdcAmount, 0);
        assertApproxEqAbs(usdcAmount, expectedUsdc, 1);
        assertEq(diamond.gatewayPoolBalance(), usdcAmount);
    }

    function test_Deposit_USDC_DirectPassthrough() public {
        uint256 amountIn = 1000e6;

        vm.startPrank(user);
        usdc.approve(address(depositor), amountIn);
        uint256 usdcAmount = depositor.deposit(user, address(usdc), amountIn, 0, "");
        vm.stopPrank();

        assertEq(usdcAmount, amountIn);
        assertEq(diamond.gatewayPoolBalance(), amountIn);
    }

    function test_Deposit_WithSlippageProtection_Success() public {
        uint256 amountIn = 1 ether;
        uint256 expectedUsdc = (amountIn * INITIAL_USDC_LIQUIDITY) / (INITIAL_WETH_LIQUIDITY + amountIn);
        uint256 minOut = expectedUsdc - 10e6;

        vm.startPrank(user);
        uint256 usdcAmount = depositor.deposit{ value: amountIn }(user, address(0), amountIn, minOut, "");
        vm.stopPrank();

        assertGt(usdcAmount, minOut);
    }

    function test_Deposit_WithSlippageProtection_Reverts() public {
        uint256 amountIn = 1 ether;
        uint256 expectedUsdc = (amountIn * INITIAL_USDC_LIQUIDITY) / (INITIAL_WETH_LIQUIDITY + amountIn);
        uint256 minOut = expectedUsdc + 1000e6;

        vm.startPrank(user);
        vm.expectRevert(DummyDexDepositor.InsufficientOutputAmount.selector);
        depositor.deposit{ value: amountIn }(user, address(0), amountIn, minOut, "");
        vm.stopPrank();
    }

    function test_Deposit_RevertsWhenInsufficientLiquidity() public {
        DummyDexDepositor emptyDepositor = new DummyDexDepositor(address(weth), address(diamond), address(usdc), owner);

        vm.startPrank(user);
        vm.expectRevert(DummyDexDepositor.InsufficientLiquidity.selector);
        emptyDepositor.deposit{ value: 1 ether }(user, address(0), 1 ether, 0, "");
        vm.stopPrank();
    }

    function test_Deposit_EmitsSwapEvent() public {
        uint256 amountIn = 1 ether;

        vm.startPrank(user);
        vm.recordLogs();
        depositor.deposit{ value: amountIn }(user, address(0), amountIn, 0, "");
        vm.stopPrank();

        Vm.Log[] memory entries = vm.getRecordedLogs();
        bool foundSwapEvent = false;
        for (uint i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == keccak256("Swap(address,uint256,uint256)")) {
                foundSwapEvent = true;
                break;
            }
        }
        assertTrue(foundSwapEvent, "Swap event not emitted");
    }

    function test_GetQuote_WETH_ReturnsCorrectAmount() public {
        uint256 amountIn = 1 ether;
        uint256 expectedUsdc = (amountIn * INITIAL_USDC_LIQUIDITY) / (INITIAL_WETH_LIQUIDITY + amountIn);

        vm.prank(user);
        weth.approve(address(depositor), amountIn);

        (bool success, bytes memory result) = address(depositor).call(
            abi.encodeWithSelector(depositor.getQuote.selector, address(weth), amountIn, "")
        );
        require(!success, "getQuote should revert");

        uint256 quotedAmount = _extractCalculatedAmountOut(result);
        assertApproxEqAbs(quotedAmount, expectedUsdc, 1);
    }

    function test_GetQuote_NativeToken_ReturnsCorrectAmount() public {
        uint256 amountIn = 1 ether;
        uint256 expectedUsdc = (amountIn * INITIAL_USDC_LIQUIDITY) / (INITIAL_WETH_LIQUIDITY + amountIn);

        vm.deal(address(this), amountIn);
        (bool success, bytes memory result) = address(depositor).call{value: amountIn}(
            abi.encodeWithSelector(depositor.getQuote.selector, address(0), amountIn, "")
        );
        require(!success, "getQuote should revert");

        uint256 quotedAmount = _extractCalculatedAmountOut(result);
        assertApproxEqAbs(quotedAmount, expectedUsdc, 1);
    }

    function test_GetQuote_USDC_ReturnsInputAmount() public {
        uint256 amountIn = 1000e6;

        (bool success, bytes memory result) = address(depositor).call(
            abi.encodeWithSelector(depositor.getQuote.selector, address(usdc), amountIn, "")
        );
        require(!success, "getQuote should revert");

        uint256 quotedAmount = _extractCalculatedAmountOut(result);
        assertEq(quotedAmount, amountIn);
    }

    function test_ReceiveFunction_Reverts() public {
        vm.expectRevert("Use deposit() for native token deposits");
        payable(address(depositor)).transfer(1 ether);
    }

    function _extractCalculatedAmountOut(bytes memory errorData) internal pure returns (uint256) {
        require(errorData.length >= 36, "Invalid error data");
        bytes4 selector;
        uint256 amount;
        assembly {
            selector := mload(add(errorData, 0x20))
            amount := mload(add(errorData, 0x24))
        }
        require(selector == LibErrors.CalculatedAmountOut.selector, "Unexpected error selector");
        return amount;
    }
}
