// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.24;

struct AuthSignature {
    bytes signature;
    uint256 deadline;
}

struct Transaction {
    uint256 timestamp;
    uint256 amount;
}
