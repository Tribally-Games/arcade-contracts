// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import { UniswapV3SwapAdapter } from "src/adapters/UniswapV3SwapAdapter.sol";
import { MockUniswapV3Router } from "./mocks/MockUniswapV3Router.sol";
import { MockQuoterV2 } from "./mocks/MockQuoterV2.sol";
import { TestERC20 } from "src/mocks/TestERC20.sol";
import { IERC20 } from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract UniswapV3SwapAdapterTest is Test {
    UniswapV3SwapAdapter public adapter;
    MockUniswapV3Router public router;
    MockQuoterV2 public quoter;
    TestERC20 public weth;
    TestERC20 public usdc;

    address public owner = address(this);
    address public user = address(0x1234);
    address public nonOwner = address(0x5678);

    uint256 public constant INITIAL_ROUTER_USDC = 1_000_000e6;

    event TokensRescued(address indexed token, address indexed to, uint256 amount);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    receive() external payable {}

    function setUp() public {
        weth = new TestERC20("Wrapped Ether", "WETH", 18);
        usdc = new TestERC20("USD Coin", "USDC", 6);
        router = new MockUniswapV3Router(address(usdc));
        quoter = new MockQuoterV2();

        vm.prank(owner);
        adapter = new UniswapV3SwapAdapter(address(router), address(quoter));

        usdc.mint(address(router), INITIAL_ROUTER_USDC);

        weth.mint(user, 100 ether);

        vm.label(owner, "Owner");
        vm.label(user, "User");
        vm.label(nonOwner, "NonOwner");
    }

    function test_Constructor_RevertsWhenRouterIsZeroAddress() public {
        vm.expectRevert(UniswapV3SwapAdapter.InvalidAddress.selector);
        new UniswapV3SwapAdapter(address(0), address(quoter));
    }

    function test_Constructor_RevertsWhenQuoterIsZeroAddress() public {
        vm.expectRevert(UniswapV3SwapAdapter.InvalidAddress.selector);
        new UniswapV3SwapAdapter(address(router), address(0));
    }

    function test_Constructor_SetsCorrectAddresses() public view {
        assertEq(adapter.swapRouter(), address(router));
        assertEq(adapter.quoterV2(), address(quoter));
        assertEq(adapter.owner(), owner);
    }

    function test_Constructor_SetsDeployerAsOwner() public {
        address deployer = address(0x1111);
        vm.prank(deployer);
        UniswapV3SwapAdapter newAdapter = new UniswapV3SwapAdapter(address(router), address(quoter));
        assertEq(newAdapter.owner(), deployer);
    }

    function test_Swap_Success() public {
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

    function test_Swap_WithMinimumOutput() public {
        uint256 amountIn = 1 ether;
        uint256 minOut = 1900e6;
        bytes memory path = abi.encodePacked(address(weth), uint24(3000), address(usdc));

        vm.startPrank(user);
        weth.approve(address(adapter), amountIn);
        uint256 amountOut = adapter.swap(address(weth), amountIn, minOut, path);
        vm.stopPrank();

        assertGt(amountOut, minOut);
    }

    function test_Swap_RevertsWhenSlippageTooHigh() public {
        uint256 amountIn = 1 ether;
        uint256 minOut = 3000e6;
        bytes memory path = abi.encodePacked(address(weth), uint24(3000), address(usdc));

        vm.startPrank(user);
        weth.approve(address(adapter), amountIn);
        vm.expectRevert("Insufficient output amount");
        adapter.swap(address(weth), amountIn, minOut, path);
        vm.stopPrank();
    }

    function test_Swap_RevertsWhenInsufficientAllowance() public {
        bytes memory path = abi.encodePacked(address(weth), uint24(3000), address(usdc));

        vm.prank(user);
        vm.expectRevert();
        adapter.swap(address(weth), 1 ether, 0, path);
    }

    function test_Swap_RevertsWhenInsufficientBalance() public {
        bytes memory path = abi.encodePacked(address(weth), uint24(3000), address(usdc));

        vm.startPrank(user);
        weth.approve(address(adapter), 200 ether);
        vm.expectRevert();
        adapter.swap(address(weth), 200 ether, 0, path);
        vm.stopPrank();
    }

    function test_Swap_TransfersUsdcToSender() public {
        uint256 amountIn = 1 ether;
        bytes memory path = abi.encodePacked(address(weth), uint24(3000), address(usdc));

        uint256 userUsdcBefore = usdc.balanceOf(user);

        vm.startPrank(user);
        weth.approve(address(adapter), amountIn);
        uint256 amountOut = adapter.swap(address(weth), amountIn, 0, path);
        vm.stopPrank();

        assertEq(usdc.balanceOf(user), userUsdcBefore + amountOut);
    }

    function test_Swap_MultipleSwapsInSequence() public {
        bytes memory path = abi.encodePacked(address(weth), uint24(3000), address(usdc));

        vm.startPrank(user);
        weth.approve(address(adapter), 10 ether);

        adapter.swap(address(weth), 1 ether, 0, path);
        adapter.swap(address(weth), 2 ether, 0, path);
        adapter.swap(address(weth), 0.5 ether, 0, path);

        vm.stopPrank();

        assertEq(usdc.balanceOf(user), ((1 ether + 2 ether + 0.5 ether) * 2000) / 1e12);
    }

    function test_RescueTokens_Success() public {
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
        vm.expectRevert(UniswapV3SwapAdapter.OnlyOwner.selector);
        adapter.rescueTokens(address(usdc), 1000e6);
    }

    function test_RescueTokens_CanRescueEth() public {
        uint256 rescueAmount = 1 ether;
        vm.deal(address(adapter), rescueAmount);

        uint256 ownerBalanceBefore = owner.balance;

        vm.expectEmit(true, true, true, true);
        emit TokensRescued(address(0), owner, rescueAmount);

        adapter.rescueTokens(address(0), rescueAmount);

        assertEq(owner.balance, ownerBalanceBefore + rescueAmount);
        assertEq(address(adapter).balance, 0);
    }

    function test_RescueTokens_CanRescueWeth() public {
        uint256 rescueAmount = 10 ether;
        weth.mint(address(adapter), rescueAmount);

        uint256 ownerBalanceBefore = weth.balanceOf(owner);

        adapter.rescueTokens(address(weth), rescueAmount);

        assertEq(weth.balanceOf(owner), ownerBalanceBefore + rescueAmount);
    }

    function test_TransferOwnership_Success() public {
        address newOwner = address(0x9999);

        vm.expectEmit(true, true, true, true);
        emit OwnershipTransferred(owner, newOwner);

        adapter.transferOwnership(newOwner);

        assertEq(adapter.owner(), newOwner);
    }

    function test_TransferOwnership_RevertsWhenNotOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert(UniswapV3SwapAdapter.OnlyOwner.selector);
        adapter.transferOwnership(address(0x9999));
    }

    function test_TransferOwnership_RevertsWhenNewOwnerIsZeroAddress() public {
        vm.expectRevert(UniswapV3SwapAdapter.InvalidAddress.selector);
        adapter.transferOwnership(address(0));
    }

    function test_TransferOwnership_NewOwnerCanRescueTokens() public {
        address newOwner = address(0x9999);
        adapter.transferOwnership(newOwner);

        usdc.mint(address(adapter), 1000e6);

        vm.prank(newOwner);
        adapter.rescueTokens(address(usdc), 1000e6);

        assertEq(usdc.balanceOf(newOwner), 1000e6);
    }
}
