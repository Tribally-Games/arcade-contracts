// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.24;

import { LibAppStorage } from "src/libs/LibAppStorage.sol";

abstract contract ReentrancyGuard {
  uint256 private constant _NOT_ENTERED = 1;
  uint256 private constant _ENTERED = 2;

  modifier nonReentrant() {
    require(
      LibAppStorage.diamondStorage().reentrancyStatus != _ENTERED,
      "ReentrancyGuard: reentrant call"
    );

    LibAppStorage.diamondStorage().reentrancyStatus = _ENTERED;

    _;

    LibAppStorage.diamondStorage().reentrancyStatus = _NOT_ENTERED;
  }
}
