// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IKatanaRouter {
    /// @notice Execute commands on Katana AggregateRouter
    /// @param commands Encoded command bytes
    /// @param inputs Array of encoded inputs for each command
    /// @param deadline Transaction deadline
    function execute(
        bytes calldata commands,
        bytes[] calldata inputs,
        uint256 deadline
    ) external payable;
}
