// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../../src/KintoID.sol";
import "@kinto-core-script/utils/MigrationHelper.sol";

contract KintoMigration33DeployScript is MigrationHelper {
    using ECDSAUpgradeable for bytes32;

    function run() public override {
        super.run();
        address DEFENDER_KYC_PROVIDER = 0x6E31039abF8d248aBed57E307C9E1b7530c269E4;
        bytes32 role = keccak256("DEFENDER_KYC_PROVIDER");
        KintoID kintoID = KintoID(_getChainDeployment("KintoID"));

        vm.broadcast();
        kintoID.grantRole(role, DEFENDER_KYC_PROVIDER);

        assertTrue(kintoID.hasRole(role, DEFENDER_KYC_PROVIDER));
    }
}
