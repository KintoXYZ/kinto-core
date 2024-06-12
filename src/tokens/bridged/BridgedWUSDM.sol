// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {BridgedToken} from "./BridgedToken.sol";
import {IKintoID} from "@kinto-core/interfaces/IKintoID.sol";
import {IKintoWallet} from "@kinto-core/interfaces/IKintoWallet.sol";
import {IKintoWalletFactory} from "@kinto-core/interfaces/IKintoWalletFactory.sol";

/**
 * @title BridgedWusdm
 * @notice Implements an ERC20 token with transfer restrictions for USA accounts.
 * Extends BridgedToken.
 */
contract BridgedWusdm is BridgedToken {
    /**
     * @notice Constructor to initialize the BridgedWusdm contract with specified decimals.
     * @param decimals_ The number of decimals for the token.
     */
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(uint8 decimals_) BridgedToken(decimals_) {}

    error TransferNotAllowed(address from, address to, uint256 countryId);

    /**
     * @dev Transfers a `value` amount of tokens from `from` to `to`, or alternatively mints (or burns) if `from`
     * (or `to`) is the zero address. All customizations to transfers, mints, and burns should be done by overriding
     * this function.
     *
     * If destination is a KintoWallet, allow all transfer except for KintoWallet with USA trait.
     *
     * Emits a {Transfer} event.
     */
    function _update(address from, address to, uint256 amount) internal override {
        if (IKintoWalletFactory(0x8a4720488CA32f1223ccFE5A087e250fE3BC5D75).walletTs(to) > 0) {
            address owner = IKintoWallet(to).owners(0);
            if (IKintoID(0xf369f78E3A0492CC4e96a90dae0728A38498e9c7).hasTrait(owner, 840)) {
                revert TransferNotAllowed(from, to, 840);
            }
        }
        super._update(from, to, amount);
    }
}
