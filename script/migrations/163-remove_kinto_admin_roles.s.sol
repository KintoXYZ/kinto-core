// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import {KintoID} from "@kinto-core/KintoID.sol";

import {IAccessControl} from "@openzeppelin-5.0.1/contracts/access/IAccessControl.sol";

import "forge-std/console2.sol";

/**
 * Migration script to remove the following roles from KintoAdminMultisig:
 * - DEFAULT_ADMIN_ROLE: Controls all access control roles
 * - UPGRADER_ROLE: Can upgrade without delay
 * - GOVERNANCE_ROLE: Can confirm sanctions
 */
contract DeployScript is MigrationHelper {
    function run() public override {
        // Call parent's run method to set up environment
        super.run();

        // Verify admin roles before removal
        console2.log("Checking roles before removal:");
        console2.log(
            "KintoAdminMultisig has DEFAULT_ADMIN_ROLE:",
            kintoID.hasRole(kintoID.DEFAULT_ADMIN_ROLE(), kintoAdminWallet)
        );
        console2.log(
            "KintoAdminMultisig has UPGRADER_ROLE:", kintoID.hasRole(kintoID.UPGRADER_ROLE(), kintoAdminWallet)
        );
        console2.log(
            "KintoAdminMultisig has GOVERNANCE_ROLE:", kintoID.hasRole(kintoID.GOVERNANCE_ROLE(), kintoAdminWallet)
        );

        // Revoke UPGRADER_ROLE
        _handleOps(
            abi.encodeWithSelector(IAccessControl.revokeRole.selector, kintoID.UPGRADER_ROLE(), kintoAdminWallet),
            address(kintoID)
        );

        // Revoke GOVERNANCE_ROLE
        _handleOps(
            abi.encodeWithSelector(IAccessControl.revokeRole.selector, kintoID.GOVERNANCE_ROLE(), kintoAdminWallet),
            address(kintoID)
        );
        // Revoke DEFAULT_ADMIN_ROLE
        _handleOps(
            abi.encodeWithSelector(IAccessControl.revokeRole.selector, kintoID.DEFAULT_ADMIN_ROLE(), kintoAdminWallet),
            address(kintoID)
        );

        // Verify roles were successfully removed
        console2.log("Checking roles after removal:");
        console2.log(
            "KintoAdminMultisig has DEFAULT_ADMIN_ROLE:",
            kintoID.hasRole(kintoID.DEFAULT_ADMIN_ROLE(), kintoAdminWallet)
        );
        console2.log(
            "KintoAdminMultisig has UPGRADER_ROLE:", kintoID.hasRole(kintoID.UPGRADER_ROLE(), kintoAdminWallet)
        );
        console2.log(
            "KintoAdminMultisig has GOVERNANCE_ROLE:", kintoID.hasRole(kintoID.GOVERNANCE_ROLE(), kintoAdminWallet)
        );

        // Assert that role removals were successful
        require(!kintoID.hasRole(kintoID.DEFAULT_ADMIN_ROLE(), kintoAdminWallet), "DEFAULT_ADMIN_ROLE removal failed");
        require(!kintoID.hasRole(kintoID.UPGRADER_ROLE(), kintoAdminWallet), "UPGRADER_ROLE removal failed");
        require(!kintoID.hasRole(kintoID.GOVERNANCE_ROLE(), kintoAdminWallet), "GOVERNANCE_ROLE removal failed");

        console2.log("Successfully removed admin roles from KintoAdminMultisig");
    }
}
