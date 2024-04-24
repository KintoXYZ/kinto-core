// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {IERC20} from "@openzeppelin-5.0.1/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin-5.0.1/contracts/token/ERC20/utils/SafeERC20.sol";
import {Address} from "@openzeppelin-5.0.1/contracts/utils/Address.sol";

import {IAccessPoint} from "../../interfaces/IAccessPoint.sol";

contract SwapWorkflow {
    using SafeERC20 for IERC20;
    using Address for address;

    address public immutable exchangeProxy;

    event SwapExecuted(address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut);

    constructor(address _exchangeProxy) {
        exchangeProxy = _exchangeProxy;
    }

    function fillQuote(
        IERC20 tokenIn,
        uint256 amountIn,
        IERC20 tokenOut,
        uint256 minAmountOut,
        bytes calldata swapCallData
    ) external {
        tokenIn.safeIncreaseAllowance(exchangeProxy, amountIn);

        exchangeProxy.functionCall(swapCallData);

        emit SwapExecuted(tokenIn, tokenOut, amountIn, minAmountOut);
    }
}
