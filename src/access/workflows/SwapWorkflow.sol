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

    event SwapExecuted(address indexed tokenIn, uint256 amountIn, address indexed tokenOut, uint256 amountOut);

    error AmountOutTooLow(uint256 amountOut, uint256 minAmountOut);

    constructor(address _exchangeProxy) {
        exchangeProxy = _exchangeProxy;
    }

    function fillQuote(
        IERC20 tokenIn,
        uint256 amountIn,
        IERC20 tokenOut,
        uint256 minAmountOut,
        bytes calldata swapCallData
    ) external returns (uint256 amountOut) {
        tokenIn.safeIncreaseAllowance(exchangeProxy, amountIn);

        uint256 balanceBeforeSwap = tokenOut.balanceOf(address(this));

        exchangeProxy.functionCall(swapCallData);

        amountOut = tokenOut.balanceOf(address(this)) - balanceBeforeSwap;
        if (amountOut < minAmountOut) revert AmountOutTooLow(amountOut, minAmountOut);

        emit SwapExecuted(address(tokenIn), amountIn, address(tokenOut), amountOut);
    }
}
