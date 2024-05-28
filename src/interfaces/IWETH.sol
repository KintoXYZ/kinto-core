// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title Interface for WETH
interface IWETH {
    /**
     * @notice Error thrown when an ETH transfer fails.
     * @param target The address to which the transfer was attempted.
     * @param amount The amount of ETH that was attempted to transfer.
     */
    error EthTransferFailed(address target, uint256 amount);

    /**
     * @notice Deposit Ether and mint wrapped tokens to the sender's address.
     */
    function deposit() external payable;

    /**
     * @notice Deposit Ether and mint wrapped tokens to a specified address.
     * @param account The address to which the wrapped tokens will be minted.
     */
    function depositTo(address account) external payable;

    /**
     * @notice Withdraw wrapped tokens and send Ether to the sender's address.
     * @param amount The amount of wrapped tokens to withdraw.
     */
    function withdraw(uint256 amount) external;

    /**
     * @notice Withdraw wrapped tokens and send Ether to a specified address.
     * @param account The address to which the Ether will be sent.
     * @param amount The amount of wrapped tokens to withdraw.
     */
    function withdrawTo(address account, uint256 amount) external;
}
