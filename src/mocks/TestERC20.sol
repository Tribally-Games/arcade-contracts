// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract TestERC20 is ERC20 {
    constructor() ERC20("TestUSDC", "tUSDC") {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) external {
        _burn(account, amount);
    }    
}
