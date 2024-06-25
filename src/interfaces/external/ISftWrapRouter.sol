// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title Interface for Solv Wrap Router
interface ISftWrapRouter {
    function createSubscription(bytes32 poolId, uint256 currencyAmount) external returns (uint256 shareValue);
}
