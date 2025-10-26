// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import { TestBaseContract, MockERC20 } from "./utils/TestBaseContract.sol";
import { LibErrors } from "src/libs/LibErrors.sol";
import { AuthSignature } from "src/shared/Structs.sol";
import { DummyDexAdapter } from "src/adapters/DummyDexAdapter.sol";
import { MockWETH } from "src/mocks/MockWETH.sol";
import { IDiamondCut } from "lib/diamond-2-hardhat/contracts/interfaces/IDiamondCut.sol";
import { ConfigFacet } from "src/facets/ConfigFacet.sol";

interface IGatewayFacet {
  function gatewayPoolBalance() external view returns (uint);
  function deposit(
    address _user,
    address _token,
    uint256 _amount,
    uint256 _minUsdcAmount,
    bytes calldata _swapData
  ) external payable;
  function calculateUsdc(address _token, uint256 _amount, bytes calldata _swapData) external returns (uint256);
  function withdraw(address _user, uint _amount, AuthSignature calldata _sig) external;
}

interface IConfigFacet {
  function signer() external view returns (address);
  function setSigner(address _signer) external;
  function govToken() external view returns (address);
  function setGovToken(address _govToken) external;
  function usdcToken() external view returns (address);
  function swapAdapter() external view returns (address);
  function updateSwapAdapter(address _newAdapter) external;
}

contract GatewayTest is TestBaseContract {
  IGatewayFacet gatewayFacet;
  IConfigFacet configFacet;
  DummyDexAdapter swapAdapter;
  MockWETH weth;
  MockERC20 otherToken;

  uint256 constant INITIAL_WETH_LIQUIDITY = 100 ether;
  uint256 constant INITIAL_USDC_LIQUIDITY = 200_000e6;

  function setUp() public virtual override {
    super.setUp();

    gatewayFacet = IGatewayFacet(diamond);
    configFacet = IConfigFacet(diamond);

    weth = new MockWETH();
    vm.prank(owner);
    swapAdapter = new DummyDexAdapter(address(weth), address(usdcToken));
    otherToken = new MockERC20();


    configFacet.updateSwapAdapter(address(swapAdapter));

    usdcToken.mint(owner, INITIAL_USDC_LIQUIDITY * 2);
    weth.deposit{ value: INITIAL_WETH_LIQUIDITY * 2 }();
    weth.approve(address(swapAdapter), type(uint256).max);
    usdcToken.approve(address(swapAdapter), type(uint256).max);
    swapAdapter.addLiquidity(INITIAL_WETH_LIQUIDITY, INITIAL_USDC_LIQUIDITY);

    usdcToken.mint(account1, 100_000e6);
    weth.deposit{ value: 100 ether }();
    weth.transfer(account1, 100 ether);
    otherToken.mint(account1, 100_000 ether);

    vm.deal(account1, 100 ether);
  }

  function test_Deposit_UsdcDirect_Success() public {
    uint256 amount = 1000e6;

    vm.startPrank(account1);
    usdcToken.approve(diamond, amount);
    gatewayFacet.deposit(account1, address(usdcToken), amount, 0, "");
    vm.stopPrank();

    assertEq(usdcToken.balanceOf(account1), 100_000e6 - amount);
    assertEq(usdcToken.balanceOf(diamond), amount);
    assertEq(gatewayFacet.gatewayPoolBalance(), amount);
  }

  function test_Deposit_UsdcDirect_EmitsEvent() public {
    uint256 amount = 1000e6;

    vm.recordLogs();

    vm.startPrank(account1);
    usdcToken.approve(diamond, amount);
    gatewayFacet.deposit(account1, address(usdcToken), amount, 0, "");
    vm.stopPrank();

    Vm.Log[] memory entries = vm.getRecordedLogs();

    bool foundEvent = false;
    for (uint i = 0; i < entries.length; i++) {
      if (entries[i].topics[0] == keccak256("TriballyGatewayDeposit(address,address,uint256,uint256)")) {
        foundEvent = true;
        assertEq(address(uint160(uint256(entries[i].topics[1]))), account1);
        assertEq(address(uint160(uint256(entries[i].topics[2]))), address(usdcToken));
      }
    }
    assertTrue(foundEvent, "Event not emitted");
  }

  function test_Deposit_NativeToken_Success() public {
    uint256 amount = 1 ether;
    uint256 expectedUsdc = (amount * INITIAL_USDC_LIQUIDITY) / (INITIAL_WETH_LIQUIDITY + amount);

    vm.prank(account1);
    gatewayFacet.deposit{ value: amount }(account1, address(0), amount, 0, "");

    assertGt(gatewayFacet.gatewayPoolBalance(), 0);
    assertApproxEqAbs(gatewayFacet.gatewayPoolBalance(), expectedUsdc, 1);
  }

  function test_Deposit_NativeToken_RevertsWhenMsgValueMismatch() public {
    uint256 amount = 1 ether;

    vm.prank(account1);
    vm.expectRevert(LibErrors.InvalidInputs.selector);
    gatewayFacet.deposit{ value: 0.5 ether }(account1, address(0), amount, 0, "");
  }

  function test_Deposit_Weth_Success() public {
    uint256 amount = 1 ether;
    uint256 expectedUsdc = (amount * INITIAL_USDC_LIQUIDITY) / (INITIAL_WETH_LIQUIDITY + amount);

    vm.startPrank(account1);
    weth.approve(diamond, amount);
    gatewayFacet.deposit(account1, address(weth), amount, 0, "");
    vm.stopPrank();

    assertEq(weth.balanceOf(account1), 100 ether - amount);
    assertGt(gatewayFacet.gatewayPoolBalance(), 0);
    assertApproxEqAbs(gatewayFacet.gatewayPoolBalance(), expectedUsdc, 1);
  }

  function test_Deposit_WithSlippageProtection_Success() public {
    uint256 amount = 1 ether;
    uint256 expectedUsdc = (amount * INITIAL_USDC_LIQUIDITY) / (INITIAL_WETH_LIQUIDITY + amount);
    uint256 minUsdc = expectedUsdc - 10e6;

    vm.prank(account1);
    gatewayFacet.deposit{ value: amount }(account1, address(0), amount, minUsdc, "");

    assertGt(gatewayFacet.gatewayPoolBalance(), minUsdc);
  }

  function test_Deposit_WithSlippageProtection_Reverts() public {
    uint256 amount = 1 ether;
    uint256 expectedUsdc = (amount * INITIAL_USDC_LIQUIDITY) / (INITIAL_WETH_LIQUIDITY + amount);
    uint256 minUsdc = expectedUsdc + 1000e6;

    vm.prank(account1);
    vm.expectRevert();
    gatewayFacet.deposit{ value: amount }(account1, address(0), amount, minUsdc, "");
  }

  function test_Deposit_MultipleDeposits_AccumulatesBalance() public {
    vm.startPrank(account1);
    usdcToken.approve(diamond, 3000e6);

    gatewayFacet.deposit(account1, address(usdcToken), 1000e6, 0, "");
    assertEq(gatewayFacet.gatewayPoolBalance(), 1000e6);

    gatewayFacet.deposit(account1, address(usdcToken), 1000e6, 0, "");
    assertEq(gatewayFacet.gatewayPoolBalance(), 2000e6);

    gatewayFacet.deposit(account1, address(usdcToken), 1000e6, 0, "");
    assertEq(gatewayFacet.gatewayPoolBalance(), 3000e6);

    vm.stopPrank();
  }

  function test_Deposit_OnBehalfOfOtherUser() public {
    uint256 amount = 1000e6;

    vm.startPrank(account2);
    usdcToken.approve(diamond, amount);
    usdcToken.mint(account2, amount);

    vm.recordLogs();
    gatewayFacet.deposit(account1, address(usdcToken), amount, 0, "");
    vm.stopPrank();

    assertEq(usdcToken.balanceOf(account2), 0);
    assertEq(gatewayFacet.gatewayPoolBalance(), amount);

    Vm.Log[] memory entries = vm.getRecordedLogs();
    bool foundEvent = false;
    for (uint i = 0; i < entries.length; i++) {
      if (entries[i].topics[0] == keccak256("TriballyGatewayDeposit(address,address,uint256,uint256)")) {
        foundEvent = true;
        assertEq(address(uint160(uint256(entries[i].topics[1]))), account1);
      }
    }
    assertTrue(foundEvent);
  }

  function test_CalculateUsdc_UsdcDirect_ReturnsAmount() public {
    uint256 amount = 1000e6;
    uint256 usdcOut = gatewayFacet.calculateUsdc(address(usdcToken), amount, "");
    assertEq(usdcOut, amount);
  }

  function test_CalculateUsdc_NativeToken_ReturnsQuote() public {
    uint256 amount = 1 ether;
    uint256 usdcOut = gatewayFacet.calculateUsdc(address(0), amount, "");
    assertGt(usdcOut, 0);
  }


  function test_Withdraw_Fails_IfBadSignature() public {
    _setupDeposit();

    vm.prank(account1);
    vm.expectRevert(abi.encodeWithSelector(LibErrors.SignatureInvalid.selector, account1));
    gatewayFacet.withdraw(account1, 100, _computeDefaultSig(
      bytes(""),
      block.timestamp + 10 seconds
    ));
  }

  function test_Withdraw_Fails_IfExpiredSignature() public {
    _setupDeposit();

    vm.prank(account1);
    vm.expectRevert(abi.encodeWithSelector(LibErrors.SignatureExpired.selector, account1));
    gatewayFacet.withdraw(account1, 100, _computeDefaultSig(
      abi.encodePacked(account1, uint(100)),
      block.timestamp - 1 seconds
    ));
  }

  function test_Withdraw_Fails_IfWrongSigner() public {
    _setupDeposit();

    vm.prank(account1);
    vm.expectRevert(abi.encodeWithSelector(LibErrors.SignatureInvalid.selector, account1));
    gatewayFacet.withdraw(account1, 1, _computeSig(
      account2_key,
      abi.encodePacked(account1, uint(1)),
      block.timestamp + 10 seconds
    ));
  }

  function test_Withdraw_Fails_IfSignatureAlreadyUsed() public {
    _setupDeposit();

    AuthSignature memory sig = _computeDefaultSig(
      abi.encodePacked(account1, uint(1)),
      block.timestamp + 10 seconds
    );

    vm.startPrank(account1);

    gatewayFacet.withdraw(account1, 1, sig);

    vm.expectRevert(abi.encodeWithSelector(LibErrors.SignatureAlreadyUsed.selector, account1));
    gatewayFacet.withdraw(account1, 1, sig);

    vm.stopPrank();
  }

  function test_Withdraw_Fails_IfNotEnoughBalance() public {
    _setupDeposit();

    vm.expectRevert(abi.encodeWithSelector(LibErrors.InsufficientBalanceError.selector));
    gatewayFacet.withdraw(account1, 101, _computeDefaultSig(
      abi.encodePacked(account1, uint(101)),
      block.timestamp + 10 seconds
    ));
  }

  function test_Withdraw_Succeeds_UpdatesBalances() public {
    _setupDeposit();

    gatewayFacet.withdraw(account1, 1, _computeDefaultSig(
      abi.encodePacked(account1, uint(1)),
      block.timestamp + 10 seconds
    ));

    assertEq(usdcToken.balanceOf(account1), 100_000e6 - 100 + 1);
    assertEq(usdcToken.balanceOf(diamond), 100 - 1);
    assertEq(gatewayFacet.gatewayPoolBalance(), 100 - 1);
  }

  function test_Withdraw_Succeeds_EmitsEvent() public {
    _setupDeposit();

    vm.recordLogs();

    gatewayFacet.withdraw(account1, 1, _computeDefaultSig(
      abi.encodePacked(account1, uint(1)),
      block.timestamp + 10 seconds
    ));

    Vm.Log[] memory entries = vm.getRecordedLogs();

    bool foundEvent = false;
    for (uint i = 0; i < entries.length; i++) {
      if (entries[i].topics[0] == keccak256("TriballyGatewayWithdraw(address,uint256)")) {
        foundEvent = true;
        (address user, uint amount) = abi.decode(entries[i].data, (address,uint256));
        assertEq(user, account1, "Invalid user");
        assertEq(amount, 1, "Invalid amount");
      }
    }
    assertTrue(foundEvent, "Event not emitted");
  }

  function test_Withdraw_Succeeds_NonDefaultSigner() public {
    _setupDeposit();

    vm.prank(owner);
    configFacet.setSigner(account2);

    gatewayFacet.withdraw(account1, 1, _computeSig(
      account2_key,
      abi.encodePacked(account1, uint(1)),
      block.timestamp + 10 seconds
    ));

    assertEq(usdcToken.balanceOf(account1), 100_000e6 - 100 + 1);
    assertEq(usdcToken.balanceOf(diamond), 100 - 1);
    assertEq(gatewayFacet.gatewayPoolBalance(), 100 - 1);
  }

  function test_UpdateSwapAdapter_Success() public {
    address newAdapter = address(0x9999);

    vm.prank(owner);
    configFacet.updateSwapAdapter(newAdapter);

    assertEq(configFacet.swapAdapter(), newAdapter);
  }

  function test_UpdateSwapAdapter_RevertsWhenNotAdmin() public {
    address newAdapter = address(0x9999);

    vm.prank(account1);
    vm.expectRevert(LibErrors.CallerMustBeAdminError.selector);
    configFacet.updateSwapAdapter(newAdapter);
  }

  function test_UpdateSwapAdapter_RevertsWhenZeroAddress() public {
    vm.prank(owner);
    vm.expectRevert(LibErrors.InvalidSwapAdapter.selector);
    configFacet.updateSwapAdapter(address(0));
  }

  function _setupDeposit() internal {
    vm.startPrank(account1);
    usdcToken.approve(diamond, 100);
    gatewayFacet.deposit(account1, address(usdcToken), 100, 0, "");
    vm.stopPrank();

    assertEq(usdcToken.balanceOf(account1), 100_000e6 - 100);
    assertEq(usdcToken.balanceOf(diamond), 100);
    assertEq(gatewayFacet.gatewayPoolBalance(), 100);
  }
}
