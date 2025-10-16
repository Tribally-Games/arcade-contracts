// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.24;

import { LibAuth } from "src/libs/LibAuth.sol";
import { AuthSignature } from "src/shared/Structs.sol";

contract SigningFacet {
  function generateSignaturePayload(bytes calldata _data, uint _deadline) external view returns (bytes memory) {
    return LibAuth.generateSignaturePayload(_data, _deadline);
  }
}
