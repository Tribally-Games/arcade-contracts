// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.24;

import { AppStorage, LibAppStorage } from "src/libs/LibAppStorage.sol";
import { AccessControl } from "src/shared/AccessControl.sol";
import { LibErrors } from "src/libs/LibErrors.sol";

contract ConfigFacet is AccessControl {
  event TribalTokenChanged(address newTribalToken);

  event SignerChanged(address newSigner);

  function signer() external view returns (address) {
    return LibAppStorage.diamondStorage().signer;
  }

  function setSigner(address _signer) external isAdmin {
    if (_signer == address(0)) {
      revert LibErrors.InvalidSignerError();
    }

    LibAppStorage.diamondStorage().signer = _signer;

    emit SignerChanged(_signer);
  }

  function tribalToken() external view returns (address) {
    return LibAppStorage.diamondStorage().tribalToken;
  }

  function setTribalToken(address _tribalToken) external isAdmin {
    if (_tribalToken == address(0)) {
      revert LibErrors.InvalidTribalTokenError();
    }

    LibAppStorage.diamondStorage().tribalToken = _tribalToken;

    emit TribalTokenChanged(_tribalToken);
  }
}
