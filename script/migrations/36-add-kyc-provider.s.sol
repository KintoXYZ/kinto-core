// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../../src/KintoID.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";

contract KintoMigration36DeployScript is MigrationHelper {
    function run() public override {
        super.run();
        address DEFENDER_KYC_PROVIDER = 0x6E31039abF8d248aBed57E307C9E1b7530c269E4;
        KintoID kintoID = KintoID(_getChainDeployment("KintoID"));

        // revoke DEFENDER_KYC_PROVIDER from relayer
        bytes32 role = keccak256("DEFENDER_KYC_PROVIDER");
        vm.broadcast();
        kintoID.revokeRole(role, DEFENDER_KYC_PROVIDER);
        assertFalse(kintoID.hasRole(role, DEFENDER_KYC_PROVIDER));

        // grant KYC_PROVIDER_ROLE to relayer
        role = kintoID.KYC_PROVIDER_ROLE();
        vm.broadcast();
        kintoID.grantRole(role, DEFENDER_KYC_PROVIDER);
        assertTrue(kintoID.hasRole(role, DEFENDER_KYC_PROVIDER));
    }
}
