// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {AccessManager} from "@openzeppelin-5.0.1/contracts/access/manager/AccessManager.sol";
import {IAccessControl} from "@openzeppelin-5.0.1/contracts/access/IAccessControl.sol";
import {KintoID} from "@kinto-core/KintoID.sol";

import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";

import "forge-std/console2.sol";

/**
 * @title Update KintoID execution delay script
 * @notice This script updates the execution delay for KintoID contract roles
 * managed by AccessManager
 */
contract DeployScript is MigrationHelper {
    // New execution delay to set for KintoID contract roles
    uint32 public constant NEW_EXECUTION_DELAY = 11 days;

    function run() public override {
        super.run();

        // Fetch deployed contracts
        AccessManager accessManager = AccessManager(_getChainDeployment("AccessManager"));
        KintoID kintoID = KintoID(_getChainDeployment("KintoID"));

        console2.log("Updating execution delay for KintoID roles");
        console2.log("Current chain ID:", block.chainid);
        console2.log("AccessManager address:", address(accessManager));
        console2.log("KintoID address:", address(kintoID));
        console2.log("New execution delay:", NEW_EXECUTION_DELAY);

        // Get the target accounts with roles that need updated execution delay
        // We use L1_SECURITY_COUNCIL from script 160 as an example
        address L1_SECURITY_COUNCIL = 0x28fC10E12A78f986c78F973Fc70ED88072b34c8e; // L1 Security Council address

        // Check if the security council has the roles before updating
        (bool hasUpgraderRole, uint32 currentUpgraderDelay) = accessManager.hasRole(UPGRADER_ROLE, L1_SECURITY_COUNCIL);
        if (hasUpgraderRole) {
            console2.log("Security Council has UPGRADER_ROLE with delay:", currentUpgraderDelay);

            // Update the execution delay for UPGRADER_ROLE
            _handleOps(
                abi.encodeWithSelector(
                    AccessManager.grantRole.selector,
                    UPGRADER_ROLE,
                    L1_SECURITY_COUNCIL,
                    NEW_EXECUTION_DELAY // New execution delay
                ),
                address(accessManager)
            );

            // Verify the delay was updated
            (bool stillHasRole, uint32 newDelay) = accessManager.hasRole(UPGRADER_ROLE, L1_SECURITY_COUNCIL);
            assertTrue(stillHasRole, "Security Council lost UPGRADER_ROLE during update");
            assertEq(newDelay, NEW_EXECUTION_DELAY, "Execution delay was not properly updated");
            console2.log("Successfully updated UPGRADER_ROLE execution delay to:", newDelay);
        } else {
            console2.log("Security Council does not have UPGRADER_ROLE, skipping update");
        }
    }
}
