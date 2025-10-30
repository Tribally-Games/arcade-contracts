// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20 } from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

interface IWETH {
    function deposit() external payable;
    function withdraw(uint256) external;
    function balanceOf(address) external view returns (uint256);
    function transfer(address, uint256) external returns (bool);
}

contract MockUniversalRouter {
    uint256 private constant WRAP_ETH = 0x0b;
    uint256 private constant V3_SWAP_EXACT_IN = 0x00;
    address private constant ADDRESS_THIS = address(2);

    address public immutable weth;
    address public immutable usdc;

    uint256 public constant EXCHANGE_RATE = 2000;

    constructor(address _weth, address _usdc) {
        weth = _weth;
        usdc = _usdc;

        require(_usdc != address(0), "Invalid USDC address");
    }

    function execute(
        bytes calldata commands,
        bytes[] calldata inputs,
        uint256 /* deadline */
    ) external payable {
        uint256 numCommands = commands.length;

        for (uint256 i = 0; i < numCommands; i++) {
            uint256 command = uint8(commands[i]) & 0x3f;

            if (command == WRAP_ETH) {
                (address recipient, uint256 amount) = abi.decode(inputs[i], (address, uint256));

                address actualRecipient = recipient == ADDRESS_THIS ? address(this) : recipient;

                IWETH(weth).deposit{ value: amount }();

                if (actualRecipient != address(this)) {
                    IWETH(weth).transfer(actualRecipient, amount);
                }
            } else if (command == V3_SWAP_EXACT_IN) {
                (address recipient, uint256 amountIn, uint256 amountOutMinimum, , ) =
                    abi.decode(inputs[i], (address, uint256, uint256, bytes, bool));

                require(IERC20(weth).balanceOf(address(this)) >= amountIn, "Insufficient WETH balance in router");

                uint256 amountOut = (amountIn * EXCHANGE_RATE) / 1e12;

                require(amountOut >= amountOutMinimum, "Insufficient output amount");

                IERC20(usdc).transfer(recipient, amountOut);
            }
        }
    }

    receive() external payable {}
}
