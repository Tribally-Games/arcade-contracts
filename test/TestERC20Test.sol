// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import { TestERC20 } from "src/mocks/TestERC20.sol";

contract TestERC20Test is Test {
    TestERC20 public token;
    address public user = address(0x1234);

    function setUp() public {
        token = new TestERC20("Test Token", "TEST", 18);
    }

    function test_Decimals_Returns18() public view {
        assertEq(token.decimals(), 18);
    }

    function test_Decimals_Returns6() public {
        TestERC20 token6 = new TestERC20("USDC", "USDC", 6);
        assertEq(token6.decimals(), 6);
    }

    function test_Mint_IncreasesBalance() public {
        uint256 mintAmount = 1000e18;

        token.mint(user, mintAmount);

        assertEq(token.balanceOf(user), mintAmount);
        assertEq(token.totalSupply(), mintAmount);
    }

    function test_Burn_DecreasesBalance() public {
        uint256 mintAmount = 1000e18;
        uint256 burnAmount = 300e18;

        token.mint(user, mintAmount);
        token.burn(user, burnAmount);

        assertEq(token.balanceOf(user), mintAmount - burnAmount);
        assertEq(token.totalSupply(), mintAmount - burnAmount);
    }

    function test_Burn_CanBurnAllTokens() public {
        uint256 mintAmount = 1000e18;

        token.mint(user, mintAmount);
        token.burn(user, mintAmount);

        assertEq(token.balanceOf(user), 0);
        assertEq(token.totalSupply(), 0);
    }
}
