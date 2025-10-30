// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import { UniversalDexDepositor } from "src/depositors/UniversalDexDepositor.sol";
import { MockDiamond } from "./mocks/MockDiamond.sol";
import { MockUniversalRouter } from "./mocks/MockUniversalRouter.sol";
import { MockWETH } from "src/mocks/MockWETH.sol";
import { TestERC20 } from "src/mocks/TestERC20.sol";
import { IERC20 } from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { LibErrors } from "src/libs/LibErrors.sol";

contract UniversalDexDepositorTest is Test {
    UniversalDexDepositor public depositor;
    MockDiamond public diamond;
    MockUniversalRouter public router;
    MockWETH public weth;
    TestERC20 public usdc;

    address public owner = address(this);
    address public user = address(0x1234);
    address public nonOwner = address(0x5678);

    uint256 public constant INITIAL_ROUTER_USDC = 1_000_000e6;

    event TokensRescued(address indexed token, address indexed to, uint256 amount);
    event SwapDeadlineUpdated(uint256 oldDeadline, uint256 newDeadline);

    function setUp() public {
        weth = new MockWETH();
        usdc = new TestERC20("USD Coin", "USDC", 6);
        diamond = new MockDiamond(address(usdc));
        router = new MockUniversalRouter(address(weth), address(usdc));

        vm.prank(owner);
        depositor = new UniversalDexDepositor(address(router), address(diamond), address(usdc), owner);

        usdc.mint(address(router), INITIAL_ROUTER_USDC);

        vm.deal(user, 1000 ether);
        weth.deposit{ value: 100 ether }();
        weth.transfer(user, 100 ether);
        usdc.mint(user, 100_000e6);

        vm.label(owner, "Owner");
        vm.label(user, "User");
        vm.label(nonOwner, "NonOwner");
    }

    function test_Constructor_RevertsWhenRouterIsZeroAddress() public {
        vm.expectRevert(UniversalDexDepositor.InvalidAddress.selector);
        new UniversalDexDepositor(address(0), address(diamond), address(usdc), owner);
    }

    function test_Constructor_RevertsWhenDiamondIsZeroAddress() public {
        vm.expectRevert(UniversalDexDepositor.InvalidAddress.selector);
        new UniversalDexDepositor(address(router), address(0), address(usdc), owner);
    }

    function test_Constructor_RevertsWhenUsdcIsZeroAddress() public {
        vm.expectRevert(UniversalDexDepositor.InvalidAddress.selector);
        new UniversalDexDepositor(address(router), address(diamond), address(0), owner);
    }

    function test_Constructor_RevertsWhenOwnerIsZeroAddress() public {
        vm.expectRevert(UniversalDexDepositor.InvalidAddress.selector);
        new UniversalDexDepositor(address(router), address(diamond), address(usdc), address(0));
    }

    function test_Constructor_SetsCorrectAddresses() public view {
        assertEq(depositor.universalRouter(), address(router));
        assertEq(depositor.diamondProxy(), address(diamond));
        assertEq(depositor.usdcToken(), address(usdc));
        assertEq(depositor.owner(), owner);
    }

    function test_Constructor_SetsDeployerAsOwner() public {
        address deployer = address(0x1111);
        vm.prank(deployer);
        UniversalDexDepositor newDepositor = new UniversalDexDepositor(address(router), address(diamond), address(usdc), deployer);
        assertEq(newDepositor.owner(), deployer);
    }

    function test_Deposit_NativeToken_Success() public {
        uint256 amountIn = 1 ether;
        uint256 expectedOut = (amountIn * 2000) / 1e12;
        bytes memory path = abi.encodePacked(address(weth), uint24(3000), address(usdc));

        vm.prank(user);
        uint256 usdcAmount = depositor.deposit{ value: amountIn }(user, address(0), amountIn, 0, path);

        assertEq(usdcAmount, expectedOut);
        assertEq(diamond.gatewayPoolBalance(), expectedOut);
    }

    function test_Deposit_NativeToken_WithMinimumOutput() public {
        uint256 amountIn = 1 ether;
        uint256 expectedOut = (amountIn * 2000) / 1e12;
        uint256 minOut = expectedOut - 10e6;
        bytes memory path = abi.encodePacked(address(weth), uint24(3000), address(usdc));

        vm.prank(user);
        uint256 usdcAmount = depositor.deposit{ value: amountIn }(user, address(0), amountIn, minOut, path);

        assertGt(usdcAmount, minOut);
        assertEq(diamond.gatewayPoolBalance(), usdcAmount);
    }

    function test_Deposit_NativeToken_RevertsWhenBelowMinimum() public {
        uint256 amountIn = 1 ether;
        uint256 minOut = 10_000e6;
        bytes memory path = abi.encodePacked(address(weth), uint24(3000), address(usdc));

        vm.prank(user);
        vm.expectRevert();
        depositor.deposit{ value: amountIn }(user, address(0), amountIn, minOut, path);
    }

    function test_Deposit_WETH_Success() public {
        uint256 amountIn = 1 ether;
        uint256 expectedOut = (amountIn * 2000) / 1e12;
        bytes memory path = abi.encodePacked(address(weth), uint24(3000), address(usdc));

        vm.startPrank(user);
        weth.approve(address(depositor), amountIn);
        uint256 usdcAmount = depositor.deposit(user, address(weth), amountIn, 0, path);
        vm.stopPrank();

        assertEq(usdcAmount, expectedOut);
        assertEq(weth.balanceOf(user), 100 ether - amountIn);
        assertEq(diamond.gatewayPoolBalance(), expectedOut);
    }

    function test_Deposit_USDC_DirectPassthrough() public {
        uint256 amountIn = 1000e6;
        bytes memory path = "";

        vm.startPrank(user);
        usdc.approve(address(depositor), amountIn);
        uint256 usdcAmount = depositor.deposit(user, address(usdc), amountIn, 0, path);
        vm.stopPrank();

        assertEq(usdcAmount, amountIn);
        assertEq(usdc.balanceOf(user), 100_000e6 - amountIn);
        assertEq(diamond.gatewayPoolBalance(), amountIn);
    }

    function test_GetQuote_NativeToken_ReturnsCorrectAmount() public {
        uint256 amountIn = 1 ether;
        uint256 expectedOut = (amountIn * 2000) / 1e12;
        bytes memory path = abi.encodePacked(address(weth), uint24(3000), address(usdc));

        vm.deal(address(this), amountIn);
        (bool success, bytes memory result) = address(depositor).call{value: amountIn}(
            abi.encodeWithSelector(depositor.getQuote.selector, address(0), amountIn, path)
        );
        require(!success, "getQuote should revert");

        uint256 quotedAmount = _extractCalculatedAmountOut(result);
        assertEq(quotedAmount, expectedOut);
    }

    function test_GetQuote_WETH_ReturnsCorrectAmount() public {
        uint256 amountIn = 1 ether;
        uint256 expectedOut = (amountIn * 2000) / 1e12;
        bytes memory path = abi.encodePacked(address(weth), uint24(3000), address(usdc));

        vm.startPrank(user);
        weth.approve(address(depositor), amountIn);

        (bool success, bytes memory result) = address(depositor).call(
            abi.encodeWithSelector(depositor.getQuote.selector, address(weth), amountIn, path)
        );
        vm.stopPrank();

        require(!success, "getQuote should revert");

        uint256 quotedAmount = _extractCalculatedAmountOut(result);
        assertEq(quotedAmount, expectedOut);
    }

    function test_GetQuote_USDC_ReturnsInputAmount() public {
        uint256 amountIn = 1000e6;
        bytes memory path = "";

        (bool success, bytes memory result) = address(depositor).call(
            abi.encodeWithSelector(depositor.getQuote.selector, address(usdc), amountIn, path)
        );
        require(!success, "getQuote should revert");

        uint256 quotedAmount = _extractCalculatedAmountOut(result);
        assertEq(quotedAmount, amountIn);
    }

    function test_SetSwapDeadline_Success() public {
        uint256 newDeadline = 600;

        vm.expectEmit(true, true, false, true);
        emit SwapDeadlineUpdated(300, newDeadline);

        depositor.setSwapDeadline(newDeadline);

        assertEq(depositor.swapDeadline(), newDeadline);
    }

    function test_SetSwapDeadline_RevertsWhenNotOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert();
        depositor.setSwapDeadline(600);
    }

    function test_SetSwapDeadline_RevertsWhenZero() public {
        vm.expectRevert(UniversalDexDepositor.InvalidDeadline.selector);
        depositor.setSwapDeadline(0);
    }

    function test_RescueTokens_Success() public {
        uint256 rescueAmount = 1000e6;
        usdc.mint(address(depositor), rescueAmount);

        uint256 ownerBalanceBefore = usdc.balanceOf(owner);

        vm.expectEmit(true, true, false, true);
        emit TokensRescued(address(usdc), owner, rescueAmount);

        depositor.rescueTokens(address(usdc), rescueAmount);

        assertEq(usdc.balanceOf(owner), ownerBalanceBefore + rescueAmount);
        assertEq(usdc.balanceOf(address(depositor)), 0);
    }

    function test_RescueTokens_RevertsWhenNotOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert();
        depositor.rescueTokens(address(usdc), 1000e6);
    }

    function test_RescueTokens_RevertsWhenZeroAddress() public {
        vm.expectRevert(UniversalDexDepositor.InvalidAddress.selector);
        depositor.rescueTokens(address(0), 1000e6);
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
