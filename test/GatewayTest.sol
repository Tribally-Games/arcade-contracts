// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import { TestBaseContract } from "./utils/TestBaseContract.sol";
import { LibErrors } from "src/libs/LibErrors.sol";
import { AuthSignature } from "src/shared/Structs.sol";

interface IGatewayFacet {
  function gatewayPoolBalance() external view returns (uint);
  function deposit(address _user, uint _amount) external;
  function withdraw(address _user, uint _amount, AuthSignature calldata _sig) external;
}

interface IConfigFacet {
  function signer() external view returns (address);
  function setSigner(address _signer) external;
  function tribalToken() external view returns (address);
  function setTribalToken(address _tribalToken) external;
}

contract GatewayTest is TestBaseContract {
  IGatewayFacet gatewayFacet;
  IConfigFacet configFacet;

  function setUp() public virtual override {
    super.setUp();

    gatewayFacet = IGatewayFacet(diamond);
    configFacet = IConfigFacet(diamond);

    tribalToken.mint(account1, 100);

    vm.prank(account1);
    tribalToken.approve(address(diamond), 101);
  }

  function test_Deposit_FailsIfNotEnoughBalance() public {
    vm.prank(account1);
    vm.expectRevert();
    gatewayFacet.deposit(account1, 101);
  }

  function test_Deposit_FailsIfNotEnoughAllowance() public {
    vm.prank(account1);
    tribalToken.approve(address(diamond), 99);

    vm.prank(account1);
    vm.expectRevert();
    gatewayFacet.deposit(account1, 100);
  }

  function test_Deposit_Success_TransfersTokens() public {
    vm.prank(account1);
    gatewayFacet.deposit(account1, 100);

    assertEq(0, tribalToken.balanceOf(account1));
    assertEq(100, tribalToken.balanceOf(address(diamond)));
    assertEq(100, gatewayFacet.gatewayPoolBalance());
  }

  function test_Deposit_Success_EmitsEvent() public {
    vm.recordLogs();

    vm.prank(account1);
    gatewayFacet.deposit(account1, 100);

    Vm.Log[] memory entries = vm.getRecordedLogs();

    assertEq(entries.length, 3, "Invalid entry count");
    assertEq(
        entries[2].topics[0],
        keccak256("TriballyGatewayDeposit(address,uint256)"),
        "Invalid event signature"
    );
    (address user, uint amount) = abi.decode(entries[2].data, (address,uint256));
    assertEq(user, account1, "Invalid user");
    assertEq(amount, 100, "Invalid amount");
  }

  function test_Deposit_Success_OnBehalfOfOtherUser() public {
    vm.prank(account2);
    tribalToken.approve(address(diamond), 100);
    tribalToken.mint(account2, 100);

    vm.prank(account2);
    gatewayFacet.deposit(account1, 100);

    assertEq(0, tribalToken.balanceOf(account2));
    assertEq(100, tribalToken.balanceOf(address(diamond)));
    assertEq(100, gatewayFacet.gatewayPoolBalance());
  }

  function test_Deposit_Success_NullAddressUser() public {
    vm.recordLogs();

    vm.prank(account1);
    gatewayFacet.deposit(address(0), 100);

    assertEq(0, tribalToken.balanceOf(account1));
    assertEq(100, tribalToken.balanceOf(address(diamond)));
    assertEq(100, gatewayFacet.gatewayPoolBalance());

    Vm.Log[] memory entries = vm.getRecordedLogs();

    assertEq(entries.length, 3, "Invalid entry count");
    assertEq(
        entries[2].topics[0],
        keccak256("TriballyGatewayDeposit(address,uint256)"),
        "Invalid event signature"
    );
    (address user, uint amount) = abi.decode(entries[2].data, (address,uint256));
    assertEq(user, address(0), "Invalid user");
    assertEq(amount, 100, "Invalid amount");
  }

  function _setupDeposit() internal {
    vm.prank(account1);
    gatewayFacet.deposit(account1, 100);

    assertEq(0, tribalToken.balanceOf(account1));
    assertEq(100, tribalToken.balanceOf(address(diamond)));
    assertEq(100, gatewayFacet.gatewayPoolBalance());
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

    assertEq(1, tribalToken.balanceOf(account1));
    assertEq(99, tribalToken.balanceOf(address(diamond)));
    assertEq(99, gatewayFacet.gatewayPoolBalance());
  }

  function test_Withdraw_Succeeds_EmitsEvent() public {
    _setupDeposit();

    vm.recordLogs();

    gatewayFacet.withdraw(account1, 1, _computeDefaultSig(
      abi.encodePacked(account1, uint(1)),
      block.timestamp + 10 seconds
    ));

    Vm.Log[] memory entries = vm.getRecordedLogs();

    assertEq(entries.length, 2, "Invalid entry count");
    assertEq(
        entries[1].topics[0],
        keccak256("TriballyGatewayWithdraw(address,uint256)"),
        "Invalid event signature"
    );
    (address user, uint amount) = abi.decode(entries[1].data, (address,uint256));
    assertEq(user, account1, "Invalid user");
    assertEq(amount, 1, "Invalid amount");
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

    assertEq(1, tribalToken.balanceOf(account1));
    assertEq(99, tribalToken.balanceOf(address(diamond)));
    assertEq(99, gatewayFacet.gatewayPoolBalance());
  }

}
