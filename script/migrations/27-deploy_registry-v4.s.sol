// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../../src/paymasters/SponsorPaymaster.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import {KintoAppRegistry} from "@kinto-core/apps/KintoAppRegistry.sol";

contract KintoMigration27DeployScript is MigrationHelper {
    function run() public override {
        super.run();

        bytes memory bytecode =
            abi.encodePacked(type(KintoAppRegistry).creationCode, abi.encode(_getChainDeployment("KintoWalletFactory")));
        _deployImplementationAndUpgrade("KintoAppRegistry", "V4", bytecode);

        // -- sanity checks --

        // check KintoID is set on Registry
        IKintoAppRegistry registry = IKintoAppRegistry(_getChainDeployment("KintoAppRegistry"));

        // check we can't call registerApp without being KYC'd
        try registry.registerApp(
            "test", address(0), new address[](0), [uint256(0), uint256(0), uint256(0), uint256(0)], new address[](0)
        ) {
            revert("registerApp should revert");
        } catch Error(string memory reason) {
            require(
                keccak256(abi.encodePacked(reason)) == keccak256(abi.encodePacked("KYC required")), "unexpected error"
            );
        }
    }
}
