// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../../src/interfaces/IKintoEntryPoint.sol";
import "../../src/interfaces/IKintoID.sol";
import "../../src/interfaces/IKintoAppRegistry.sol";

import {KintoAppRegistry} from "../../src/apps/KintoAppRegistry.sol";
import "@kinto-core/paymasters/SponsorPaymaster.sol";

// Harness contract to expose internal functions for testing.
contract KintoAppRegistryHarness is KintoAppRegistry {
    constructor(IKintoWalletFactory _walletFactory, SponsorPaymaster _paymaster)
        KintoAppRegistry(_walletFactory, _paymaster)
    {}

    function exposed_baseURI() public pure returns (string memory) {
        return _baseURI();
    }
}
