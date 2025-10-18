// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../../lib/openzeppelin-contracts/contracts/mocks/ERC20Mock.sol";

contract TestERC20 is ERC20Mock {
    function decimals() public pure override returns (uint8) {
        return 6;
    }
}
