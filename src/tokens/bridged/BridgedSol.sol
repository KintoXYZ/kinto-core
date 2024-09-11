// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {BridgedToken} from "./BridgedToken.sol";

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
