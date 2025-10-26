// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import { TestBaseContract } from "./utils/TestBaseContract.sol";
import { LibErrors } from "src/libs/LibErrors.sol";
import { InitDiamond } from "src/init/InitDiamond.sol";
import { IDiamondCut } from "lib/diamond-2-hardhat/contracts/interfaces/IDiamondCut.sol";

interface IConfigFacet {
  function signer() external view returns (address);
  function setSigner(address _signer) external;
  function govToken() external view returns (address);
  function setGovToken(address _govToken) external;
  function usdcToken() external view returns (address);
}

contract ConfigTest is TestBaseContract {
  IConfigFacet configFacet;

  function setUp() public virtual override {
    super.setUp();
    configFacet = IConfigFacet(diamond);
  }

  function test_GovToken_ReturnsInitializedAddress() public {
    assertEq(configFacet.govToken(), address(govToken));
  }

  function test_SetGovToken_FailsIfNotAdmin() public {
    address newToken = address(0x123);

    vm.prank(account1);
    vm.expectRevert(abi.encodeWithSelector(LibErrors.CallerMustBeAdminError.selector));
    configFacet.setGovToken(newToken);
  }

  function test_SetGovToken_FailsIfZeroAddress() public {
    vm.prank(owner);
    vm.expectRevert(abi.encodeWithSelector(LibErrors.InvalidGovTokenError.selector));
    configFacet.setGovToken(address(0));
  }

  function test_SetGovToken_SucceedsWithValidAddress() public {
    address newToken = address(0x123);

    vm.recordLogs();

    vm.prank(owner);
    configFacet.setGovToken(newToken);

    assertEq(configFacet.govToken(), newToken);

    Vm.Log[] memory entries = vm.getRecordedLogs();
    assertEq(entries.length, 1, "Invalid entry count");
    assertEq(
        entries[0].topics[0],
        keccak256("GovTokenChanged(address)"),
        "Invalid event signature"
    );
  }

  function test_UsdcToken_ReturnsInitializedAddress() public {
    assertEq(configFacet.usdcToken(), address(usdcToken));
  }

  function test_UsdcToken_CannotBeChanged() public {
    bytes4 selector = bytes4(keccak256("setUsdcToken(address)"));
    bytes memory data = abi.encodeWithSelector(selector, address(0x123));

    vm.prank(owner);
    (bool success, ) = diamond.call(data);

    assertFalse(success, "setUsdcToken should not exist");
  }

  function test_Signer_ReturnsInitializedAddress() public {
    assertEq(configFacet.signer(), signer);
  }

  function test_SetSigner_FailsIfNotAdmin() public {
    address newSigner = address(0x456);

    vm.prank(account1);
    vm.expectRevert(abi.encodeWithSelector(LibErrors.CallerMustBeAdminError.selector));
    configFacet.setSigner(newSigner);
  }

  function test_SetSigner_FailsIfZeroAddress() public {
    vm.prank(owner);
    vm.expectRevert(abi.encodeWithSelector(LibErrors.InvalidSignerError.selector));
    configFacet.setSigner(address(0));
  }

  function test_SetSigner_SucceedsWithValidAddress() public {
    address newSigner = address(0x456);

    vm.recordLogs();

    vm.prank(owner);
    configFacet.setSigner(newSigner);

    assertEq(configFacet.signer(), newSigner);

    Vm.Log[] memory entries = vm.getRecordedLogs();
    assertEq(entries.length, 1, "Invalid entry count");
    assertEq(
        entries[0].topics[0],
        keccak256("SignerChanged(address)"),
        "Invalid event signature"
    );
  }

  function test_MultipleGovTokenUpdates() public {
    address token1 = address(0x111);
    address token2 = address(0x222);
    address token3 = address(0x333);

    vm.startPrank(owner);

    configFacet.setGovToken(token1);
    assertEq(configFacet.govToken(), token1);

    configFacet.setGovToken(token2);
    assertEq(configFacet.govToken(), token2);

    configFacet.setGovToken(token3);
    assertEq(configFacet.govToken(), token3);

    vm.stopPrank();
  }

  function test_Init_FailsIfAlreadyInitialized() public {
    InitDiamond init = new InitDiamond();
    IDiamondCut.FacetCut[] memory cuts = new IDiamondCut.FacetCut[](0);

    vm.expectRevert(abi.encodeWithSignature("DiamondAlreadyInitialized()"));
    IDiamondCut(diamond).diamondCut(
      cuts,
      address(init),
      abi.encodeWithSelector(init.init.selector, address(govToken), address(usdcToken), signer, address(0x1))
    );
  }
}
