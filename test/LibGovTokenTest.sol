// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import { TestBaseContract } from "./utils/TestBaseContract.sol";
import { TestGovTokenFacet } from "./utils/TestGovTokenFacet.sol";
import { IDiamondCut } from "lib/diamond-2-hardhat/contracts/interfaces/IDiamondCut.sol";

interface ITestGovTokenFacet {
  function transferFromGovToken(address _from, uint256 _amount) external;
  function transferToGovToken(address _to, uint256 _amount) external;
}

contract LibGovTokenTest is TestBaseContract {
  ITestGovTokenFacet testFacet;

  function setUp() public virtual override {
    super.setUp();

    TestGovTokenFacet testGovTokenFacet = new TestGovTokenFacet();

    bytes4[] memory selectors = new bytes4[](2);
    selectors[0] = TestGovTokenFacet.transferFromGovToken.selector;
    selectors[1] = TestGovTokenFacet.transferToGovToken.selector;

    IDiamondCut.FacetCut[] memory cuts = new IDiamondCut.FacetCut[](1);
    cuts[0] = IDiamondCut.FacetCut({
      facetAddress: address(testGovTokenFacet),
      action: IDiamondCut.FacetCutAction.Add,
      functionSelectors: selectors
    });

    IDiamondCut(diamond).diamondCut(cuts, address(0), "");

    testFacet = ITestGovTokenFacet(diamond);

    govToken.mint(account1, 1000);
    vm.prank(account1);
    govToken.approve(diamond, 1000);
  }

  function test_LibGovToken_TransferFrom() public {
    uint256 initialBalance = govToken.balanceOf(account1);
    uint256 initialDiamondBalance = govToken.balanceOf(diamond);

    vm.prank(account1);
    testFacet.transferFromGovToken(account1, 100);

    assertEq(govToken.balanceOf(account1), initialBalance - 100);
    assertEq(govToken.balanceOf(diamond), initialDiamondBalance + 100);
  }

  function test_LibGovToken_TransferTo() public {
    govToken.mint(diamond, 500);

    uint256 initialBalance = govToken.balanceOf(account1);
    uint256 initialDiamondBalance = govToken.balanceOf(diamond);

    testFacet.transferToGovToken(account1, 200);

    assertEq(govToken.balanceOf(account1), initialBalance + 200);
    assertEq(govToken.balanceOf(diamond), initialDiamondBalance - 200);
  }
}
