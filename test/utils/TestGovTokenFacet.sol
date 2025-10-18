// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.24;

import { LibGovToken } from "src/libs/LibGovToken.sol";

contract TestGovTokenFacet {
  function transferFromGovToken(address _from, uint256 _amount) external {
    LibGovToken.transferFrom(_from, _amount);
  }

  function transferToGovToken(address _to, uint256 _amount) external {
    LibGovToken.transferTo(_to, _amount);
  }
}
