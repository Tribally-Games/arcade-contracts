// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import { TestBaseContract, MockERC20 } from "./utils/TestBaseContract.sol";
import { LibErrors } from "src/libs/LibErrors.sol";
import { AuthSignature } from "src/shared/Structs.sol";
import { ConfigFacet } from "src/facets/ConfigFacet.sol";

interface IGatewayFacet {
  function gatewayPoolBalance() external view returns (uint);
  function deposit(address _user, uint256 _amount) external;
  function withdraw(address _user, uint _amount, AuthSignature calldata _sig) external;
}

interface IConfigFacet {
  function signer() external view returns (address);
  function setSigner(address _signer) external;
  function govToken() external view returns (address);
  function setGovToken(address _govToken) external;
  function usdcToken() external view returns (address);
}

contract GatewayTest is TestBaseContract {
  IGatewayFacet gatewayFacet;
  IConfigFacet configFacet;

  function setUp() public virtual override {
    super.setUp();

    gatewayFacet = IGatewayFacet(diamond);
    configFacet = IConfigFacet(diamond);

    usdcToken.mint(account1, 100_000e6);
    usdcToken.mint(account2, 100_000e6);
  }

  function test_Deposit_Success() public {
    uint256 amount = 1000e6;

    vm.startPrank(account1);
    usdcToken.approve(diamond, amount);
    gatewayFacet.deposit(account1, amount);
    vm.stopPrank();

    assertEq(usdcToken.balanceOf(account1), 100_000e6 - amount);
    assertEq(usdcToken.balanceOf(diamond), amount);
    assertEq(gatewayFacet.gatewayPoolBalance(), amount);
  }

  function test_Deposit_EmitsEvent() public {
    uint256 amount = 1000e6;

    vm.recordLogs();

    vm.startPrank(account1);
    usdcToken.approve(diamond, amount);
    gatewayFacet.deposit(account1, amount);
    vm.stopPrank();

    Vm.Log[] memory entries = vm.getRecordedLogs();

    bool foundEvent = false;
    for (uint i = 0; i < entries.length; i++) {
      if (entries[i].topics[0] == keccak256("TriballyGatewayDeposit(address,uint256)")) {
        foundEvent = true;
        assertEq(address(uint160(uint256(entries[i].topics[1]))), account1);
      }
    }
    assertTrue(foundEvent, "Event not emitted");
  }

  function test_Deposit_MultipleDeposits_AccumulatesBalance() public {
    vm.startPrank(account1);
    usdcToken.approve(diamond, 3000e6);

    gatewayFacet.deposit(account1, 1000e6);
    assertEq(gatewayFacet.gatewayPoolBalance(), 1000e6);

    gatewayFacet.deposit(account1, 1000e6);
    assertEq(gatewayFacet.gatewayPoolBalance(), 2000e6);

    gatewayFacet.deposit(account1, 1000e6);
    assertEq(gatewayFacet.gatewayPoolBalance(), 3000e6);

    vm.stopPrank();
  }

  function test_Deposit_OnBehalfOfOtherUser() public {
    uint256 amount = 1000e6;

    vm.startPrank(account2);
    usdcToken.approve(diamond, amount);

    vm.recordLogs();
    gatewayFacet.deposit(account1, amount);
    vm.stopPrank();

    assertEq(usdcToken.balanceOf(account2), 100_000e6 - amount);
    assertEq(gatewayFacet.gatewayPoolBalance(), amount);

    Vm.Log[] memory entries = vm.getRecordedLogs();
    bool foundEvent = false;
    for (uint i = 0; i < entries.length; i++) {
      if (entries[i].topics[0] == keccak256("TriballyGatewayDeposit(address,uint256)")) {
        foundEvent = true;
        assertEq(address(uint160(uint256(entries[i].topics[1]))), account1);
      }
    }
    assertTrue(foundEvent);
  }

  function test_Deposit_RevertsWhenUserIsZeroAddress() public {
    uint256 amount = 1000e6;

    vm.startPrank(account1);
    usdcToken.approve(diamond, amount);
    vm.expectRevert(LibErrors.InvalidInputs.selector);
    gatewayFacet.deposit(address(0), amount);
    vm.stopPrank();
  }

  function test_Deposit_RevertsWhenAmountIsZero() public {
    vm.startPrank(account1);
    vm.expectRevert(LibErrors.InvalidInputs.selector);
    gatewayFacet.deposit(account1, 0);
    vm.stopPrank();
  }

  function test_Deposit_RevertsWhenInsufficientApproval() public {
    uint256 amount = 1000e6;

    vm.startPrank(account1);
    usdcToken.approve(diamond, amount - 1);
    vm.expectRevert();
    gatewayFacet.deposit(account1, amount);
    vm.stopPrank();
  }

  function test_Deposit_RevertsWhenInsufficientBalance() public {
    uint256 amount = 100_001e6;

    vm.startPrank(account1);
    usdcToken.approve(diamond, amount);
    vm.expectRevert();
    gatewayFacet.deposit(account1, amount);
    vm.stopPrank();
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

  function _setupDeposit() internal {
    vm.startPrank(account1);
    usdcToken.approve(diamond, 100);
    gatewayFacet.deposit(account1, 100);
    vm.stopPrank();

    assertEq(usdcToken.balanceOf(account1), 100_000e6 - 100);
    assertEq(usdcToken.balanceOf(diamond), 100);
    assertEq(gatewayFacet.gatewayPoolBalance(), 100);
  }
}
