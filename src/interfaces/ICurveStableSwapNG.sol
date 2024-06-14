// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title Interface for Curve Stable Pool
interface ICurveStableSwapNG {
    function exchange(int128 tokenInIndex, int128 tokenOutIndex, uint256 amount, uint256 mintAmountOut)
        external
        returns (uint256 amountOut);

    function coins(uint256 index) external view returns (address coin);
}
