// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin-5.0.1/contracts/proxy/beacon/UpgradeableBeacon.sol";

import "../../src/interfaces/IKintoEntryPoint.sol";
import "../../src/interfaces/IKintoID.sol";
import "../../src/interfaces/IKintoAppRegistry.sol";

import {AccessRegistry} from "../../src/access/AccessRegistry.sol";

// Harness contract to expose internal functions for testing.
contract AccessRegistryHarness is AccessRegistry {
    constructor(UpgradeableBeacon beacon_) AccessRegistry(beacon_) {
        // body intentionally blank
    }

    /// @dev Added because Kinto EntryPoint needs this function. Not needed on other chains.
    function getWalletTimestamp(address) external pure returns (uint256) {
        return 1;
    }
}
