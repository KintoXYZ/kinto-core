// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {BridgedToken} from "./BridgedToken.sol";
import {IKintoID} from "@kinto-core/interfaces/IKintoID.sol";
import {IKintoWallet} from "@kinto-core/interfaces/IKintoWallet.sol";
import {IKintoWalletFactory} from "@kinto-core/interfaces/IKintoWalletFactory.sol";

/**
 * @title BridgedSOL
 * @notice SOl has 9 decimals
 * Extends BridgedToken.
 */
contract BridgedSOL is BridgedToken {
    /**
     * @notice Constructor to initialize the BridgedSOL contract with specified decimals.
     */
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() BridgedToken(9) {}

}
