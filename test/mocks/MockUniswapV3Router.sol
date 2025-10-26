// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20 } from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { IV3SwapRouter } from "../../src/interfaces/IV3SwapRouter.sol";

contract MockUniswapV3Router is IV3SwapRouter {
    address public immutable usdc;
    uint256 public constant EXCHANGE_RATE = 2000;

    constructor(address _usdc) {
        usdc = _usdc;
    }

    function exactInput(ExactInputParams calldata params)
        external
        payable
        override
        returns (uint256 amountOut)
    {
        amountOut = (params.amountIn * EXCHANGE_RATE) / 1e12;

        require(amountOut >= params.amountOutMinimum, "Insufficient output amount");

        IERC20(usdc).transfer(params.recipient, amountOut);

        return amountOut;
    }
}
