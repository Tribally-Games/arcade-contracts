// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { IERC20 } from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

contract MockDiamond {
    using SafeERC20 for IERC20;

    uint256 public gatewayPoolBalance;
    address public usdcToken;

    event TriballyGatewayDeposit(address indexed user, uint256 amount);

    constructor(address _usdcToken) {
        usdcToken = _usdcToken;
    }

    function deposit(address _user, uint256 _amount) external {
        IERC20(usdcToken).safeTransferFrom(msg.sender, address(this), _amount);
        gatewayPoolBalance += _amount;
        emit TriballyGatewayDeposit(_user, _amount);
    }
}
