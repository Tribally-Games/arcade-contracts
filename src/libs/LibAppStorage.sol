// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.24;

import { Transaction } from "../shared/Structs.sol";

struct AppStorage {
    bool diamondInitialized;
    uint256 reentrancyStatus;

    mapping(bytes32 => bool) authSignatures;

    address govToken;

    address signer;

    mapping(address => uint) DEPRECATED_locked;

    uint gatewayPoolBalance;

    address usdcToken;

    address swapAdapter;
}


library LibAppStorage {
    bytes32 internal constant DIAMOND_APP_STORAGE_POSITION = keccak256("diamond.app.storage");

    function diamondStorage() internal pure returns (AppStorage storage ds) {
        bytes32 position = DIAMOND_APP_STORAGE_POSITION;
        assembly {
            ds.slot := position
        }
    }
}
