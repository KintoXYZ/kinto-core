// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title Interface for WETH
interface IWETH  {
    /// @notice Deposit ether to get wrapped ether
    function deposit() external payable;

    /// @notice
    function depositTo(address account) external payable;

    /// @notice Withdraw wrapped ether to get ether
    function withdraw(uint256) external;

    /// @notice 
    function withdrawTo(address account, uint256 amount) external;
}
