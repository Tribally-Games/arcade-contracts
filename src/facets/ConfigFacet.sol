// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.24;

import { AppStorage, LibAppStorage } from "src/libs/LibAppStorage.sol";
import { AccessControl } from "src/shared/AccessControl.sol";
import { LibErrors } from "src/libs/LibErrors.sol";

contract ConfigFacet is AccessControl {
  event GovTokenChanged(address newGovToken);

  event SignerChanged(address newSigner);

  event SwapAdapterUpdated(address indexed oldAdapter, address indexed newAdapter);

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

  function govToken() external view returns (address) {
    return LibAppStorage.diamondStorage().govToken;
  }

  function setGovToken(address _govToken) external isAdmin {
    if (_govToken == address(0)) {
      revert LibErrors.InvalidGovTokenError();
    }

    LibAppStorage.diamondStorage().govToken = _govToken;

    emit GovTokenChanged(_govToken);
  }

  function usdcToken() external view returns (address) {
    return LibAppStorage.diamondStorage().usdcToken;
  }

  function swapAdapter() external view returns (address) {
    return LibAppStorage.diamondStorage().swapAdapter;
  }

  function updateSwapAdapter(address _newAdapter) external isAdmin {
    AppStorage storage s = LibAppStorage.diamondStorage();

    if (_newAdapter == address(0)) {
      revert LibErrors.InvalidSwapAdapter();
    }

    address oldAdapter = s.swapAdapter;
    s.swapAdapter = _newAdapter;

    emit SwapAdapterUpdated(oldAdapter, _newAdapter);
  }
}
