// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.24;

import { LibToken } from "src/libs/LibToken.sol";
import { LibAppStorage } from "src/libs/LibAppStorage.sol";


library LibGovToken {
    function transferFrom(address _from, uint256 _amount) internal {
        address token = LibAppStorage.diamondStorage().govToken;
        LibToken.transferFrom(token, _from, _amount);
    }

    function transferTo(address _to, uint256 _amount) internal {
        address token = LibAppStorage.diamondStorage().govToken;
        LibToken.transferTo(token, _to, _amount);
    }
}
