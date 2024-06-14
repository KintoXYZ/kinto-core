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
    /// @notice The country code for USA.
    /// @dev https://en.wikipedia.org/wiki/List_of_ISO_3166_country_codes
    uint16 public constant USA_COUNTRY_ID = 840;

    /// @notice The Kinto wallet factory instance.
    address public immutable walletFactory;
    /// @notice The Kinto identification instance.
    address public immutable kintoId;

    /// @notice The error thrown if the recipient of the transfer resides in a prohibited country.
    error CountryIsNotAllowed(address from, address to, uint256 countryId);

    /**
     * @notice Constructor to initialize the BridgedWusdm contract with specified decimals.
     * @param decimals_ The number of decimals for the token.
     * @param walletFactory_ The Kinto wallet factory.
     * @param kintoId_ The Kinto identification.
     */
    constructor(uint8 decimals_, address walletFactory_, address kintoId_) BridgedToken(decimals_) {
        walletFactory = walletFactory_;
        kintoId = kintoId_;
    }

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
        super._update(from, to, amount);
        // Check if wallet associated with the `to` account.
        if (IKintoWalletFactory(walletFactory).walletTs(to) > 0) {
            address owner = IKintoWallet(to).owners(0);
            // check if the wallet from USA.
            if (IKintoID(kintoId).hasTrait(owner, USA_COUNTRY_ID)) {
                revert CountryIsNotAllowed(from, to, USA_COUNTRY_ID);
            }
        }
    }
}
