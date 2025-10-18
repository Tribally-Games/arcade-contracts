// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.24;

import { AppStorage, LibAppStorage } from "../libs/LibAppStorage.sol";

error DiamondAlreadyInitialized();

contract InitDiamond {
  event InitializeDiamond(address sender);

  function init(address _govToken, address _usdcToken, address _signer) external {
    AppStorage storage s = LibAppStorage.diamondStorage();
    if (s.diamondInitialized) {
      revert DiamondAlreadyInitialized();
    }
    s.diamondInitialized = true;

    s.govToken = _govToken;
    s.usdcToken = _usdcToken;
    s.signer = _signer;

    emit InitializeDiamond(msg.sender);
  }
}
