// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../../src/KintoID.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";

contract KintoMigration45DeployScript is MigrationHelper {
    function run() public override {
        super.run();

        // revoke KYC_PROVIDER_ROLE from old KYC provider address
        address oldKYCProvider = 0x6fe642404B7B23F31251103Ca0efb538Ad4aeC07;
        KintoID kintoID = KintoID(_getChainDeployment("KintoID"));
        bytes32 role = kintoID.KYC_PROVIDER_ROLE();

        assertTrue(kintoID.hasRole(role, oldKYCProvider));

        vm.broadcast();
        kintoID.revokeRole(role, oldKYCProvider);

        assertFalse(kintoID.hasRole(role, oldKYCProvider));
    }
}
