// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title Interface for Angle swapper
interface IAngleSwapper {
    /// @notice Swaps (that is to say mints or burns) an exact amount of `tokenIn` for an amount of `tokenOut`
    /// @param amountIn Amount of `tokenIn` to bring
    /// @param amountOutMin Minimum amount of `tokenOut` to get: if `amountOut` is inferior to this amount, the
    /// function will revert
    /// @param tokenIn Token to bring for the swap
    /// @param tokenOut Token to get out of the swap
    /// @param to Address to which `tokenOut` must be sent
    /// @param deadline Timestamp before which the transaction must be executed
    /// @return amountOut Amount of `tokenOut` obtained through the swap
    function swapExactInput(
        uint256 amountIn,
        uint256 amountOutMin,
        address tokenIn,
        address tokenOut,
        address to,
        uint256 deadline
    ) external returns (uint256 amountOut);
}
