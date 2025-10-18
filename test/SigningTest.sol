// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import { TestBaseContract } from "./utils/TestBaseContract.sol";

interface ISigningFacet {
  function generateSignaturePayload(bytes calldata _data, uint _deadline) external view returns (bytes memory);
}

contract SigningTest is TestBaseContract {
  ISigningFacet signingFacet;

  function setUp() public virtual override {
    super.setUp();
    signingFacet = ISigningFacet(diamond);
  }

  function test_GenerateSignaturePayload_ReturnsCorrectHash() public view {
    bytes memory data = abi.encodePacked(account1, uint(100));
    uint deadline = block.timestamp + 10 seconds;

    bytes memory payload = signingFacet.generateSignaturePayload(data, deadline);

    assertEq(payload, abi.encodePacked(data, deadline, block.chainid));
  }
}
