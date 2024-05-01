// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {IERC20} from "@openzeppelin-5.0.1/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin-5.0.1/contracts/token/ERC20/utils/SafeERC20.sol";
import {Address} from "@openzeppelin-5.0.1/contracts/utils/Address.sol";

/**
 * @title SwapWorkflow
 * @notice Implements a token swap functionality using Ox AP.
 */
contract SwapWorkflow {
    using SafeERC20 for IERC20;
    using Address for address;

    /// @notice The address of the 0x exchange proxy through which swaps are executed.
    address public immutable exchangeProxy;

    /// @notice An event that is emitted after a successful token swap.
    event SwapExecuted(address indexed tokenIn, uint256 amountIn, address indexed tokenOut, uint256 amountOut);

    /// @notice An error that is thrown if the output amount of the swap is less than the minimum specified.
    error AmountOutTooLow(uint256 amountOut, uint256 minAmountOut);

    /**
     * @dev Initializes the contract by setting the exchange proxy address.
     * @param _exchangeProxy The address of the exchange proxy to be used for token swaps.
     */
    constructor(address _exchangeProxy) {
        exchangeProxy = _exchangeProxy;
    }

    /**
     * @notice Executes a token swap via the 0x protocol using provided swap calldata.
     * @dev Increases allowance, invokes the swap, and verifies the output. The `swapCallData` should contain all
     * necessary data for executing a swap on 0x. It does not verify if the parameters match the `swapCallData`.
     * Set the slippage at the "quote," as it is relative to the market price of the asset..
     * The `takerAddress` must be set to the access point's address in the quote to enable RFQ liquidity.
     * Both `allowanceTarget` and `to` are always set to the 0x exchange proxy.
     * For more details, visit: https://0x.org/docs/0x-swap-api/api-references/get-swap-v1-quote
     * @param tokenIn The token being swapped.
     * @param amountIn The amount of `tokenIn` being swapped.
     * @param tokenOut The token expected to be received from the swap.
     * @param swapCallData The calldata to be sent to the exchange proxy to execute the swap.
     * @return amountOut The actual amount of `tokenOut` received from the swap.
     */
    function fillQuote(IERC20 tokenIn, uint256 amountIn, IERC20 tokenOut, bytes calldata swapCallData)
        external
        returns (uint256 amountOut)
    {
        // Increase the allowance for the exchangeProxy to handle `amountIn` of `tokenIn`
        tokenIn.safeIncreaseAllowance(exchangeProxy, amountIn);

        // Store the `tokenOut` balance of this contract before the swap is executed.
        uint256 balanceBeforeSwap = tokenOut.balanceOf(address(this));

        // Perform the swap call to the exchange proxy.
        exchangeProxy.functionCall(swapCallData);

        // Calculate the output amount by subtracting the pre-swap balance from the post-swap balance.
        amountOut = tokenOut.balanceOf(address(this)) - balanceBeforeSwap;

        // Emit an event to log the successful swap.
        emit SwapExecuted(address(tokenIn), amountIn, address(tokenOut), amountOut);
    }
}
