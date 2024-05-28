// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {BridgedToken} from "@kinto-core/tokens/BridgedToken.sol";
import {IWETH} from "@kinto-core/interfaces/IWETH.sol";

/**
 * @title BridgedWeth
 * @notice
 */
contract BridgedWeth is BridgedToken, IWETH {
    /// @notice
    error EthTransferFailed(address target, uint256 amount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(uint8 decimals_) BridgedToken(decimals_) {}

    function deposit() external payable override {
        depositTo(msg.sender);
    }

    function withdraw(uint256 amount) external override {
        withdrawTo(msg.sender, amount);
    }

    function depositTo(address account) public payable {
        _mint(account, msg.value);
    }

    function withdrawTo(address account, uint256 amount) public {
        _burn(msg.sender, amount);
        (bool success, ) = account.call{ value: amount }("");
        if(!success) {
            revert EthTransferFailed( account, amount);
        }
    }

    receive() external payable {
        depositTo(msg.sender);
    }
}
