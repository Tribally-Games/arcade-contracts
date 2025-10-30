// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import { UniversalSwapAdapter } from "src/adapters/UniversalSwapAdapter.sol";
import { MockUniversalRouter } from "./mocks/MockUniversalRouter.sol";
import { MockWETH } from "src/mocks/MockWETH.sol";
import { TestERC20 } from "src/mocks/TestERC20.sol";
import { IERC20 } from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { LibErrors } from "src/libs/LibErrors.sol";

contract UniversalSwapAdapterTest is Test {
    UniversalSwapAdapter public adapter;
    MockUniversalRouter public router;
    MockWETH public weth;
    TestERC20 public usdc;

    address public owner = address(this);
    address public user = address(0x1234);
    address public nonOwner = address(0x5678);

    uint256 public constant INITIAL_ROUTER_USDC = 1_000_000e6;

    event TokensRescued(address indexed token, address indexed to, uint256 amount);

    function setUp() public {
        weth = new MockWETH();
        usdc = new TestERC20("USD Coin", "USDC", 6);
        router = new MockUniversalRouter(address(weth), address(usdc));

        vm.prank(owner);
        adapter = new UniversalSwapAdapter(address(router), owner);

        usdc.mint(address(router), INITIAL_ROUTER_USDC);

        vm.deal(user, 1000 ether);
        weth.deposit{ value: 100 ether }();
        weth.transfer(user, 100 ether);

        vm.label(owner, "Owner");
        vm.label(user, "User");
        vm.label(nonOwner, "NonOwner");
    }

    function test_Constructor_RevertsWhenRouterIsZeroAddress() public {
        vm.expectRevert(UniversalSwapAdapter.InvalidAddress.selector);
        new UniversalSwapAdapter(address(0), owner);
    }

    function test_Constructor_RevertsWhenOwnerIsZeroAddress() public {
        vm.expectRevert(UniversalSwapAdapter.InvalidAddress.selector);
        new UniversalSwapAdapter(address(router), address(0));
    }

    function test_Constructor_SetsCorrectAddresses() public view {
        assertEq(adapter.universalRouter(), address(router));
        assertEq(adapter.owner(), owner);
    }

    function test_Constructor_SetsDeployerAsOwner() public {
        address deployer = address(0x1111);
        vm.prank(deployer);
        UniversalSwapAdapter newAdapter = new UniversalSwapAdapter(address(router), deployer);
        assertEq(newAdapter.owner(), deployer);
    }

    function test_Swap_NativeToken_Success() public {
        uint256 amountIn = 1 ether;
        uint256 expectedOut = (amountIn * 2000) / 1e12;
        bytes memory path = abi.encodePacked(address(weth), uint24(3000), address(usdc));

        vm.prank(user);
        uint256 amountOut = adapter.swap{ value: amountIn }(address(0), amountIn, 0, path);

        assertEq(amountOut, expectedOut);
        assertEq(usdc.balanceOf(user), expectedOut);
    }

    function test_Swap_NativeToken_WithMinimumOutput() public {
        uint256 amountIn = 1 ether;
        uint256 minOut = 1900e6;
        bytes memory path = abi.encodePacked(address(weth), uint24(3000), address(usdc));

        vm.prank(user);
        uint256 amountOut = adapter.swap{ value: amountIn }(address(0), amountIn, minOut, path);

        assertGt(amountOut, minOut);
        assertEq(usdc.balanceOf(user), amountOut);
    }

    function test_Swap_NativeToken_RevertsWhenSlippageTooHigh() public {
        uint256 amountIn = 1 ether;
        uint256 minOut = 3000e6;
        bytes memory path = abi.encodePacked(address(weth), uint24(3000), address(usdc));

        vm.prank(user);
        vm.expectRevert("Insufficient output amount");
        adapter.swap{ value: amountIn }(address(0), amountIn, minOut, path);
    }

    function test_Swap_Weth_Success() public {
        uint256 amountIn = 1 ether;
        uint256 expectedOut = (amountIn * 2000) / 1e12;
        bytes memory path = abi.encodePacked(address(weth), uint24(3000), address(usdc));

        vm.startPrank(user);
        weth.approve(address(adapter), amountIn);
        uint256 amountOut = adapter.swap(address(weth), amountIn, 0, path);
        vm.stopPrank();

        assertEq(amountOut, expectedOut);
        assertEq(usdc.balanceOf(user), expectedOut);
        assertEq(weth.balanceOf(user), 100 ether - amountIn);
    }

    function test_Swap_Weth_RevertsWhenInsufficientAllowance() public {
        bytes memory path = abi.encodePacked(address(weth), uint24(3000), address(usdc));

        vm.prank(user);
        vm.expectRevert();
        adapter.swap(address(weth), 1 ether, 0, path);
    }

    function test_Swap_Weth_RevertsWhenInsufficientBalance() public {
        bytes memory path = abi.encodePacked(address(weth), uint24(3000), address(usdc));

        vm.startPrank(user);
        weth.approve(address(adapter), 200 ether);
        vm.expectRevert();
        adapter.swap(address(weth), 200 ether, 0, path);
        vm.stopPrank();
    }

    function test_Swap_MultipleSwapsInSequence() public {
        bytes memory path = abi.encodePacked(address(weth), uint24(3000), address(usdc));

        vm.startPrank(user);

        adapter.swap{ value: 1 ether }(address(0), 1 ether, 0, path);

        weth.approve(address(adapter), 2 ether);
        adapter.swap(address(weth), 2 ether, 0, path);

        adapter.swap{ value: 0.5 ether }(address(0), 0.5 ether, 0, path);

        vm.stopPrank();

        assertEq(usdc.balanceOf(user), ((1 ether + 2 ether + 0.5 ether) * 2000) / 1e12);
    }

    function test_GetQuote_NativeToken_ExecutesSwap() public {
        uint256 amountIn = 1 ether;
        bytes memory path = abi.encodePacked(address(weth), uint24(3000), address(usdc));

        vm.deal(address(this), amountIn);
        (bool success, bytes memory result) = address(adapter).call{value: amountIn}(
            abi.encodeWithSelector(adapter.getQuote.selector, address(0), amountIn, path)
        );
        require(!success, "call should revert");
        uint256 quoteAmount = _extractCalculatedAmountOut(result);

        uint256 expectedOut = (amountIn * 2000) / 1e12;
        assertEq(quoteAmount, expectedOut);
    }

    function test_GetQuote_Weth_ExecutesSwap() public {
        uint256 amountIn = 1 ether;
        bytes memory path = abi.encodePacked(address(weth), uint24(3000), address(usdc));

        vm.startPrank(user);
        weth.approve(address(adapter), amountIn);
        (bool success, bytes memory result) = address(adapter).call(
            abi.encodeWithSelector(adapter.getQuote.selector, address(weth), amountIn, path)
        );
        require(!success, "call should revert");
        uint256 quoteAmount = _extractCalculatedAmountOut(result);
        vm.stopPrank();

        uint256 expectedOut = (amountIn * 2000) / 1e12;
        assertEq(quoteAmount, expectedOut);
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

    function test_RescueTokens_Success() public{
        uint256 rescueAmount = 1000e6;
        usdc.mint(address(adapter), rescueAmount);

        uint256 ownerBalanceBefore = usdc.balanceOf(owner);

        vm.expectEmit(true, true, true, true);
        emit TokensRescued(address(usdc), owner, rescueAmount);

        adapter.rescueTokens(address(usdc), rescueAmount);

        assertEq(usdc.balanceOf(owner), ownerBalanceBefore + rescueAmount);
        assertEq(usdc.balanceOf(address(adapter)), 0);
    }

    function test_RescueTokens_RevertsWhenNotOwner() public {
        usdc.mint(address(adapter), 1000e6);

        vm.prank(nonOwner);
        vm.expectRevert();
        adapter.rescueTokens(address(usdc), 1000e6);
    }

    function test_RescueTokens_RevertsWhenTokenIsZeroAddress() public {
        vm.expectRevert(UniversalSwapAdapter.InvalidAddress.selector);
        adapter.rescueTokens(address(0), 1000e6);
    }

    function test_RescueTokens_CanRescueWeth() public {
        uint256 rescueAmount = 10 ether;
        weth.deposit{ value: rescueAmount }();
        weth.transfer(address(adapter), rescueAmount);

        uint256 ownerBalanceBefore = weth.balanceOf(owner);

        adapter.rescueTokens(address(weth), rescueAmount);

        assertEq(weth.balanceOf(owner), ownerBalanceBefore + rescueAmount);
    }

    function test_SwapDeadline_DefaultIs300Seconds() public view {
        assertEq(adapter.swapDeadline(), 300);
    }

    function test_SetSwapDeadline_Success() public {
        uint256 newDeadline = 600;

        vm.expectEmit(true, true, true, true);
        emit UniversalSwapAdapter.SwapDeadlineUpdated(300, newDeadline);

        adapter.setSwapDeadline(newDeadline);

        assertEq(adapter.swapDeadline(), newDeadline);
    }

    function test_SetSwapDeadline_RevertsWhenNotOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert();
        adapter.setSwapDeadline(600);
    }

    function test_SetSwapDeadline_RevertsWhenZero() public {
        vm.expectRevert(UniversalSwapAdapter.InvalidDeadline.selector);
        adapter.setSwapDeadline(0);
    }

    function test_Swap_UsesConfiguredDeadline() public {
        adapter.setSwapDeadline(120);

        uint256 amountIn = 1 ether;
        bytes memory path = abi.encodePacked(address(weth), uint24(3000), address(usdc));

        vm.prank(user);
        uint256 amountOut = adapter.swap{ value: amountIn }(address(0), amountIn, 0, path);

        assertEq(amountOut, (amountIn * 2000) / 1e12);
        assertEq(usdc.balanceOf(user), amountOut);
    }
}
