// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.24;

interface IGatewayFacet {
  function deposit(address _user, uint256 _amount) external;
}
