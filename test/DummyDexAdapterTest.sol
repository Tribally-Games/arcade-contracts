// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import { DummyDexAdapter } from "src/adapters/DummyDexAdapter.sol";
import { MockWETH } from "src/mocks/MockWETH.sol";
import { TestERC20 } from "src/mocks/TestERC20.sol";
import { IERC20 } from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract DummyDexAdapterTest is Test {
    DummyDexAdapter public adapter;
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

        vm.prank(owner);
        adapter = new DummyDexAdapter(address(weth), address(usdc));

        usdc.mint(owner, INITIAL_USDC_LIQUIDITY * 2);
        weth.deposit{ value: INITIAL_WETH_LIQUIDITY * 2 }();

        weth.approve(address(adapter), type(uint256).max);
        usdc.approve(address(adapter), type(uint256).max);

        adapter.addLiquidity(INITIAL_WETH_LIQUIDITY, INITIAL_USDC_LIQUIDITY);

        vm.deal(user, 1000 ether);
        weth.deposit{ value: 100 ether }();
        weth.transfer(user, 100 ether);
        usdc.mint(user, 100_000e6);

        vm.label(owner, "Owner");
        vm.label(user, "User");
        vm.label(nonOwner, "NonOwner");
    }

    function test_Constructor_RevertsWhenWethIsZeroAddress() public {
        vm.expectRevert(DummyDexAdapter.InvalidAddress.selector);
        new DummyDexAdapter(address(0), address(usdc));
    }

    function test_Constructor_RevertsWhenUsdcIsZeroAddress() public {
        vm.expectRevert(DummyDexAdapter.InvalidAddress.selector);
        new DummyDexAdapter(address(weth), address(0));
    }

    function test_Constructor_SetsCorrectAddresses() public view {
        assertEq(adapter.wrappedNativeToken(), address(weth));
        assertEq(adapter.usdcToken(), address(usdc));
        assertEq(adapter.owner(), owner);
    }

    function test_Constructor_SetsDeployerAsOwner() public {
        address deployer = address(0x1111);
        vm.prank(deployer);
        DummyDexAdapter newAdapter = new DummyDexAdapter(address(weth), address(usdc));
        assertEq(newAdapter.owner(), deployer);
    }

    function test_AddLiquidity_RevertsWhenNotOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert();
        adapter.addLiquidity(1 ether, 2000e6);
    }

    function test_AddLiquidity_RevertsWhenWethAmountIsZero() public {
        vm.expectRevert(DummyDexAdapter.InvalidAddress.selector);
        adapter.addLiquidity(0, 2000e6);
    }

    function test_AddLiquidity_RevertsWhenUsdcAmountIsZero() public {
        vm.expectRevert(DummyDexAdapter.InvalidAddress.selector);
        adapter.addLiquidity(1 ether, 0);
    }

    function test_AddLiquidity_UpdatesReserves() public {
        uint256 reserveWethBefore = adapter.reserveWETH();
        uint256 reserveUsdcBefore = adapter.reserveUSDC();

        adapter.addLiquidity(10 ether, 20_000e6);

        assertEq(adapter.reserveWETH(), reserveWethBefore + 10 ether);
        assertEq(adapter.reserveUSDC(), reserveUsdcBefore + 20_000e6);
    }

    function test_AddLiquidity_TransfersTokensFromOwner() public {
        uint256 wethBalanceBefore = weth.balanceOf(owner);
        uint256 usdcBalanceBefore = usdc.balanceOf(owner);

        adapter.addLiquidity(10 ether, 20_000e6);

        assertEq(weth.balanceOf(owner), wethBalanceBefore - 10 ether);
        assertEq(usdc.balanceOf(owner), usdcBalanceBefore - 20_000e6);
        assertEq(weth.balanceOf(address(adapter)), INITIAL_WETH_LIQUIDITY + 10 ether);
        assertEq(usdc.balanceOf(address(adapter)), INITIAL_USDC_LIQUIDITY + 20_000e6);
    }

    function test_AddLiquidity_EmitsEvent() public {
        vm.expectEmit(true, true, true, true);
        emit LiquidityAdded(10 ether, 20_000e6);
        adapter.addLiquidity(10 ether, 20_000e6);
    }

    function test_RemoveLiquidity_RevertsWhenNotOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert();
        adapter.removeLiquidity(1 ether, 2000e6);
    }

    function test_RemoveLiquidity_RevertsWhenInsufficientWethReserve() public {
        vm.expectRevert(DummyDexAdapter.InsufficientLiquidity.selector);
        adapter.removeLiquidity(INITIAL_WETH_LIQUIDITY + 1, 0);
    }

    function test_RemoveLiquidity_RevertsWhenInsufficientUsdcReserve() public {
        vm.expectRevert(DummyDexAdapter.InsufficientLiquidity.selector);
        adapter.removeLiquidity(0, INITIAL_USDC_LIQUIDITY + 1);
    }

    function test_RemoveLiquidity_UpdatesReserves() public {
        adapter.removeLiquidity(10 ether, 20_000e6);

        assertEq(adapter.reserveWETH(), INITIAL_WETH_LIQUIDITY - 10 ether);
        assertEq(adapter.reserveUSDC(), INITIAL_USDC_LIQUIDITY - 20_000e6);
    }

    function test_RemoveLiquidity_TransfersTokensToOwner() public {
        uint256 wethBalanceBefore = weth.balanceOf(owner);
        uint256 usdcBalanceBefore = usdc.balanceOf(owner);

        adapter.removeLiquidity(10 ether, 20_000e6);

        assertEq(weth.balanceOf(owner), wethBalanceBefore + 10 ether);
        assertEq(usdc.balanceOf(owner), usdcBalanceBefore + 20_000e6);
    }

    function test_RemoveLiquidity_EmitsEvent() public {
        vm.expectEmit(true, true, true, true);
        emit LiquidityRemoved(10 ether, 20_000e6);
        adapter.removeLiquidity(10 ether, 20_000e6);
    }

    function test_RemoveLiquidity_AllowsZeroAmounts() public {
        vm.expectEmit(true, true, true, true);
        emit LiquidityRemoved(0, 0);
        adapter.removeLiquidity(0, 0);
    }

    function test_Swap_NativeToUsdc_Success() public {
        uint256 amountIn = 1 ether;
        uint256 expectedOut = (amountIn * INITIAL_USDC_LIQUIDITY) / (INITIAL_WETH_LIQUIDITY + amountIn);

        vm.prank(user);
        uint256 amountOut = adapter.swap{ value: amountIn }(address(0), amountIn, 0, "");

        assertEq(amountOut, expectedOut);
        assertEq(usdc.balanceOf(user), 100_000e6 + expectedOut);
    }

    function test_Swap_NativeToUsdc_UpdatesReserves() public {
        uint256 amountIn = 1 ether;
        uint256 expectedOut = (amountIn * INITIAL_USDC_LIQUIDITY) / (INITIAL_WETH_LIQUIDITY + amountIn);

        vm.prank(user);
        adapter.swap{ value: amountIn }(address(0), amountIn, 0, "");

        assertEq(adapter.reserveWETH(), INITIAL_WETH_LIQUIDITY + amountIn);
        assertEq(adapter.reserveUSDC(), INITIAL_USDC_LIQUIDITY - expectedOut);
    }

    function test_Swap_NativeToUsdc_EmitsEvent() public {
        uint256 amountIn = 1 ether;
        uint256 expectedOut = (amountIn * INITIAL_USDC_LIQUIDITY) / (INITIAL_WETH_LIQUIDITY + amountIn);

        vm.expectEmit(true, true, true, true);
        emit Swap(address(0), amountIn, expectedOut);

        vm.prank(user);
        adapter.swap{ value: amountIn }(address(0), amountIn, 0, "");
    }

    function test_Swap_NativeToUsdc_RevertsWhenSlippageTooHigh() public {
        uint256 amountIn = 1 ether;
        uint256 expectedOut = (amountIn * INITIAL_USDC_LIQUIDITY) / (INITIAL_WETH_LIQUIDITY + amountIn);

        vm.prank(user);
        vm.expectRevert(DummyDexAdapter.InsufficientOutputAmount.selector);
        adapter.swap{ value: amountIn }(address(0), amountIn, expectedOut + 1, "");
    }

    function test_Swap_WethToUsdc_Success() public {
        uint256 amountIn = 1 ether;
        uint256 expectedOut = (amountIn * INITIAL_USDC_LIQUIDITY) / (INITIAL_WETH_LIQUIDITY + amountIn);

        vm.startPrank(user);
        weth.approve(address(adapter), amountIn);
        uint256 amountOut = adapter.swap(address(weth), amountIn, 0, "");
        vm.stopPrank();

        assertEq(amountOut, expectedOut);
        assertEq(usdc.balanceOf(user), 100_000e6 + expectedOut);
        assertEq(weth.balanceOf(user), 100 ether - amountIn);
    }

    function test_Swap_WethToUsdc_RevertsWhenInsufficientAllowance() public {
        vm.prank(user);
        vm.expectRevert();
        adapter.swap(address(weth), 1 ether, 0, "");
    }

    function test_Swap_WethToUsdc_RevertsWhenInsufficientBalance() public {
        vm.startPrank(user);
        weth.approve(address(adapter), 200 ether);
        vm.expectRevert();
        adapter.swap(address(weth), 200 ether, 0, "");
        vm.stopPrank();
    }

    function test_Swap_UsdcToWeth_Success() public {
        uint256 amountIn = 2000e6;
        uint256 expectedOut = (amountIn * INITIAL_WETH_LIQUIDITY) / (INITIAL_USDC_LIQUIDITY + amountIn);

        vm.startPrank(user);
        usdc.approve(address(adapter), amountIn);
        uint256 amountOut = adapter.swap(address(usdc), amountIn, 0, "");
        vm.stopPrank();

        assertEq(amountOut, expectedOut);
        assertEq(weth.balanceOf(user), 100 ether + expectedOut);
        assertEq(usdc.balanceOf(user), 100_000e6 - amountIn);
    }

    function test_Swap_UsdcToWeth_UpdatesReserves() public {
        uint256 amountIn = 2000e6;
        uint256 expectedOut = (amountIn * INITIAL_WETH_LIQUIDITY) / (INITIAL_USDC_LIQUIDITY + amountIn);

        vm.startPrank(user);
        usdc.approve(address(adapter), amountIn);
        adapter.swap(address(usdc), amountIn, 0, "");
        vm.stopPrank();

        assertEq(adapter.reserveUSDC(), INITIAL_USDC_LIQUIDITY + amountIn);
        assertEq(adapter.reserveWETH(), INITIAL_WETH_LIQUIDITY - expectedOut);
    }

    function test_Swap_UsdcToWeth_EmitsEvent() public {
        uint256 amountIn = 2000e6;

        vm.recordLogs();

        vm.startPrank(user);
        usdc.approve(address(adapter), amountIn);
        adapter.swap(address(usdc), amountIn, 0, "");
        vm.stopPrank();

        Vm.Log[] memory entries = vm.getRecordedLogs();
        bool foundSwapEvent = false;
        for (uint i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == keccak256("Swap(address,uint256,uint256)")) {
                foundSwapEvent = true;
                assertEq(address(uint160(uint256(entries[i].topics[1]))), address(usdc));
            }
        }
        assertTrue(foundSwapEvent, "Swap event not emitted");
    }

    function test_Swap_RevertsWhenInvalidToken() public {
        address invalidToken = address(0x9999);

        vm.prank(user);
        vm.expectRevert(DummyDexAdapter.InvalidToken.selector);
        adapter.swap(invalidToken, 1 ether, 0, "");
    }

    function test_Swap_RevertsWhenNoLiquidity() public {
        vm.prank(owner);
        DummyDexAdapter emptyAdapter = new DummyDexAdapter(address(weth), address(usdc));

        vm.prank(user);
        vm.expectRevert(DummyDexAdapter.InsufficientLiquidity.selector);
        emptyAdapter.swap{ value: 1 ether }(address(0), 1 ether, 0, "");
    }

    function test_Swap_LargeAmount_ReducesReserve() public {
        uint256 largeAmount = 90 ether;
        uint256 expectedOut = (largeAmount * INITIAL_USDC_LIQUIDITY) / (INITIAL_WETH_LIQUIDITY + largeAmount);

        vm.prank(user);
        vm.deal(user, 100 ether);
        uint256 amountOut = adapter.swap{ value: largeAmount }(address(0), largeAmount, 0, "");

        assertEq(amountOut, expectedOut);
        assertLt(adapter.reserveUSDC(), INITIAL_USDC_LIQUIDITY);
    }

    function test_Receive_RevertsDirectEthTransfers() public {
        vm.prank(user);
        (bool success, ) = address(adapter).call{ value: 1 ether }("");
        assertFalse(success);
    }

    function test_Swap_CfmmFormulaAccuracy() public {
        uint256 amountIn = 5 ether;
        uint256 reserveWethBefore = adapter.reserveWETH();
        uint256 reserveUsdcBefore = adapter.reserveUSDC();

        uint256 expectedOut = (amountIn * reserveUsdcBefore) / (reserveWethBefore + amountIn);

        vm.prank(user);
        uint256 actualOut = adapter.swap{ value: amountIn }(address(0), amountIn, 0, "");

        assertEq(actualOut, expectedOut);

        uint256 kBefore = reserveWethBefore * reserveUsdcBefore;
        uint256 kAfter = adapter.reserveWETH() * adapter.reserveUSDC();
        assertGt(kAfter, kBefore);
    }

    function test_Swap_MultipleSwapsInSequence() public {
        vm.startPrank(user);

        adapter.swap{ value: 1 ether }(address(0), 1 ether, 0, "");

        usdc.approve(address(adapter), 1000e6);
        adapter.swap(address(usdc), 1000e6, 0, "");

        weth.approve(address(adapter), 0.5 ether);
        adapter.swap(address(weth), 0.5 ether, 0, "");

        vm.stopPrank();

        assertGt(adapter.reserveWETH(), 0);
        assertGt(adapter.reserveUSDC(), 0);
    }
}
