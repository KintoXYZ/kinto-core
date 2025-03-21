// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {AccessManager} from "@openzeppelin-5.0.1/contracts/access/manager/AccessManager.sol";
import {IAccessControl} from "@openzeppelin-5.0.1/contracts/access/IAccessControl.sol";
import {KintoID} from "@kinto-core/KintoID.sol";

import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";

import "forge-std/console2.sol";

/**
 * @title Update Admin Role Delays
 * @notice This script:
 * 1. Updates execution delays for KintoAdminMultisig ADMIN_ROLE and UPGRADER_ROLE to 11 days
 */
contract DeployScript is MigrationHelper {
    // New execution delay to set for all roles: 11 days
    uint32 public constant NEW_DELAY = 11 days;

    // KintoAdminMultisig address
    address public constant KINTO_ADMIN_MULTISIG = 0x2e2B1c42E38f5af81771e65D87729E57ABD1337a;

    function run() public override {
        super.run();

        // Fetch deployed contracts
        AccessManager accessManager = AccessManager(_getChainDeployment("AccessManager"));

        console2.log("Starting admin role delay update script");
        console2.log("Current chain ID:", block.chainid);
        console2.log("AccessManager address:", address(accessManager));
        console2.log("KintoAdminMultisig address:", KINTO_ADMIN_MULTISIG);

        // Get the roles we need to update
        uint64 ADMIN_ROLE = accessManager.ADMIN_ROLE();

        // Update execution delays for KintoAdminMultisig ADMIN_ROLE
        (bool hasAdminRole, uint32 adminCurrentDelay) = accessManager.hasRole(ADMIN_ROLE, KINTO_ADMIN_MULTISIG);
        console2.log("KintoAdminMultisig ADMIN_ROLE current delay:", adminCurrentDelay);

        if (hasAdminRole && adminCurrentDelay < NEW_DELAY) {
            console2.log("Updating KintoAdminMultisig ADMIN_ROLE delay to 11 days");
            _handleOps(
                abi.encodeWithSelector(AccessManager.grantRole.selector, ADMIN_ROLE, KINTO_ADMIN_MULTISIG, NEW_DELAY),
                address(accessManager)
            );

            vm.warp(block.timestamp + adminCurrentDelay + 1);

            (, uint32 newAdminDelay) = accessManager.hasRole(ADMIN_ROLE, KINTO_ADMIN_MULTISIG);
            console2.log("KintoAdminMultisig ADMIN_ROLE updated delay:", newAdminDelay);
            require(newAdminDelay == NEW_DELAY, "ADMIN_ROLE delay update failed");
        } else if (hasAdminRole) {
            console2.log("KintoAdminMultisig ADMIN_ROLE delay already >= 11 days, no update needed");
        } else {
            console2.log("KintoAdminMultisig doesn't have ADMIN_ROLE");
        }

        // Update execution delays for KintoAdminMultisig UPGRADER_ROLE
        (bool hasUpgraderRole, uint32 upgraderCurrentDelay) = accessManager.hasRole(UPGRADER_ROLE, KINTO_ADMIN_MULTISIG);
        console2.log("KintoAdminMultisig UPGRADER_ROLE current delay:", upgraderCurrentDelay);

        if (hasUpgraderRole && upgraderCurrentDelay < NEW_DELAY) {
            console2.log("Scheduling update for KintoAdminMultisig UPGRADER_ROLE delay to 11 days");

            // First schedule the operation using the existing delay
            bytes memory data =
                abi.encodeWithSelector(AccessManager.grantRole.selector, UPGRADER_ROLE, KINTO_ADMIN_MULTISIG, NEW_DELAY);
            _handleOps(
                abi.encodeWithSelector(AccessManager.schedule.selector, address(accessManager), data, 0),
                address(accessManager)
            );

            uint48 scheduleTime = accessManager.getSchedule(
                accessManager.hashOperation(KINTO_ADMIN_MULTISIG, address(accessManager), data)
            );

            console2.log("scheduleTime:", scheduleTime);

            // Warp time to after the delay
            vm.warp(scheduleTime + 1);

            // Execute the operation
            vm.prank(KINTO_ADMIN_MULTISIG);
            accessManager.execute(
                address(accessManager),
                abi.encodeWithSelector(AccessManager.grantRole.selector, UPGRADER_ROLE, KINTO_ADMIN_MULTISIG, NEW_DELAY)
            );

            // Verify the delay was updated
            (, uint32 newUpgraderDelay) = accessManager.hasRole(UPGRADER_ROLE, KINTO_ADMIN_MULTISIG);
            console2.log("KintoAdminMultisig UPGRADER_ROLE updated delay:", newUpgraderDelay);
            require(newUpgraderDelay == NEW_DELAY, "UPGRADER_ROLE delay update failed");
        } else if (hasUpgraderRole) {
            console2.log("KintoAdminMultisig UPGRADER_ROLE delay already >= 11 days, no update needed");
        } else {
            console2.log("KintoAdminMultisig doesn't have UPGRADER_ROLE");
        }

        console2.log("Admin role delay update script completed successfully");
    }
}
