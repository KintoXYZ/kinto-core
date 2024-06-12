// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {BridgedToken} from "@kinto-core/tokens/bridged/BridgedToken.sol";
import {IWETH} from "@kinto-core/interfaces/IWETH.sol";

/**
 * @title BridgedWeth
 * @notice A contract for wrapping and unwrapping Ether, extending BridgedToken and implementing IWETH interface.
 */
contract BridgedWeth is BridgedToken, IWETH {
    /**
     * @notice Constructor to initialize the BridgedWeth contract with specified decimals.
     * @param decimals_ The number of decimals for the token.
     */
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(uint8 decimals_) BridgedToken(decimals_) {}

    /// @inheritdoc IWETH
    function deposit() external payable override {
        depositTo(msg.sender);
    }

    /// @inheritdoc IWETH
    function withdraw(uint256 amount) external override {
        withdrawTo(msg.sender, amount);
    }

    /// @inheritdoc IWETH
    function depositTo(address account) public payable {
        _mint(account, msg.value);
    }

    /// @inheritdoc IWETH
    function withdrawTo(address account, uint256 amount) public {
        _burn(msg.sender, amount);
        (bool success,) = account.call{value: amount}("");
        if (!success) {
            revert EthTransferFailed(account, amount);
        }
    }

    /**
     * @notice Fallback function to handle Ether received directly.
     */
    receive() external payable {
        depositTo(msg.sender);
    }
}
