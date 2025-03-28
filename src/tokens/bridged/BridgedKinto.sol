// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {NoncesUpgradeable} from "@openzeppelin-5.0.1/contracts-upgradeable/utils/NoncesUpgradeable.sol";
import {ERC20PermitUpgradeable} from
    "@openzeppelin-5.0.1/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {ERC20VotesUpgradeable} from
    "@openzeppelin-5.0.1/contracts-upgradeable/token/ERC20/extensions/ERC20VotesUpgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin-5.0.1/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

import {BridgedToken} from "@kinto-core/tokens/bridged/BridgedToken.sol";
import {IKintoID} from "@kinto-core/interfaces/IKintoID.sol";
import {IKintoWallet} from "@kinto-core/interfaces/IKintoWallet.sol";
import {IKintoWalletFactory} from "@kinto-core/interfaces/IKintoWalletFactory.sol";

/**
 * @title BridgedKinto
 * @notice Implements an ERC20 token with specific features for Kinto token.
 * Extends BridgedToken.
 */
contract BridgedKinto is BridgedToken, ERC20VotesUpgradeable {
    /// @notice DEPRECATED: Address of the mining contract.
    address private __miningContract;

    /**
     * @notice Constructor to initialize the BridgedKinto.
     */
    constructor() BridgedToken(18) {}

    /**
     * @dev Transfers a `value` amount of tokens from `from` to `to`, or alternatively mints (or burns) if `from`
     * (or `to`) is the zero address. All customizations to transfers, mints, and burns should be done by overriding
     * this function.
     *
     * Emits a {Transfer} event.
     */
    function _update(address from, address to, uint256 amount)
        internal
        override(ERC20Upgradeable, ERC20VotesUpgradeable)
    {
        super._update(from, to, amount);
    }

    function nonces(address user) public view override(ERC20PermitUpgradeable, NoncesUpgradeable) returns (uint256) {
        return super.nonces(user);
    }

    function decimals() public view override(ERC20Upgradeable, BridgedToken) returns (uint8) {
        return super.decimals();
    }

    function symbol() public pure override returns (string memory) {
        return "K";
    }

    function name() public pure override returns (string memory) {
        return "Kinto Token";
    }

    function clock() public view override returns (uint48) {
        return uint48(block.timestamp);
    }

    // solhint-disable-next-line func-name-mixedcase
    function CLOCK_MODE() public pure override returns (string memory) {
        return "mode=timestamp";
    }
}
