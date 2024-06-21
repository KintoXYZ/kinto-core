// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {BridgedToken} from "./BridgedToken.sol";
import {IKintoID} from "@kinto-core/interfaces/IKintoID.sol";
import {IKintoWallet} from "@kinto-core/interfaces/IKintoWallet.sol";
import {IKintoWalletFactory} from "@kinto-core/interfaces/IKintoWalletFactory.sol";

/**
 * @title BridgedKinto
 * @notice Implements an ERC20 token with specific features for Kinto token.
 * Extends BridgedToken.
 */
contract BridgedKinto is BridgedToken {
    /// @notice The error thrown if the recipient is not allowed.
    error TransferIsNotAllowed(address from, address to, uint256 amount);

    /// @notice Emmitted when new mining contract is set.
    event MiningContractSet(address indexed miningContract, address oldMiningContract);

    /// @notice Address of the mining contract.
    address public miningContract;

    /**
     * @notice Constructor to initialize the BridgedKinto.
     */
    constructor() BridgedToken(18) {}

    /**
     * @notice Set the mining contract address.
     * @param newMiningContract The address of the mining contract.
     */
    function setMiningContract(address newMiningContract) public onlyRole(DEFAULT_ADMIN_ROLE) {
        emit MiningContractSet(newMiningContract, miningContract);
        miningContract = newMiningContract;
    }

    /**
     * @dev Transfers a `value` amount of tokens from `from` to `to`, or alternatively mints (or burns) if `from`
     * (or `to`) is the zero address. All customizations to transfers, mints, and burns should be done by overriding
     * this function.
     *
     * Emits a {Transfer} event.
     */
    function _update(address from, address to, uint256 amount) internal override {
        super._update(from, to, amount);

        if (from != address(0) && from != address(miningContract) && to != address(miningContract)) {
            revert TransferIsNotAllowed(from, to, amount);
        }
    }
}
