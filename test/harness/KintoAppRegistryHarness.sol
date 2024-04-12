// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../../src/interfaces/IKintoEntryPoint.sol";
import "../../src/interfaces/IKintoID.sol";
import "../../src/interfaces/IKintoAppRegistry.sol";

import {KintoAppRegistry} from "../../src/apps/KintoAppRegistry.sol";

// Harness contract to expose internal functions for testing.
contract KintoAppRegistryHarness is KintoAppRegistry {
    constructor(IKintoWalletFactory _walletFactory) KintoAppRegistry(_walletFactory) {}

    function exposed_baseURI() public pure returns (string memory) {
        return _baseURI();
    }
}
