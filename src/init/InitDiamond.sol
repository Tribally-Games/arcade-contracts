// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.24;

import { AppStorage, LibAppStorage } from "../libs/LibAppStorage.sol";
import { LibErrors } from "../libs/LibErrors.sol";

error DiamondAlreadyInitialized();

contract InitDiamond {
  event InitializeDiamond(address sender);

  function init(address _govToken, address _usdcToken, address _signer, address _swapAdapter) external {
    AppStorage storage s = LibAppStorage.diamondStorage();
    if (s.diamondInitialized) {
      revert DiamondAlreadyInitialized();
    }

    if (_swapAdapter == address(0)) {
      revert LibErrors.InvalidSwapAdapter();
    }

    s.diamondInitialized = true;

    s.govToken = _govToken;
    s.usdcToken = _usdcToken;
    s.signer = _signer;
    s.swapAdapter = _swapAdapter;

    emit InitializeDiamond(msg.sender);
  }
}
