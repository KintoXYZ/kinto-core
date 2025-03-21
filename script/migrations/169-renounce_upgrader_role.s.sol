// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {AccessManager} from "@openzeppelin-5.0.1/contracts/access/manager/AccessManager.sol";
import {IAccessControl} from "@openzeppelin-5.0.1/contracts/access/IAccessControl.sol";
import {KintoID} from "@kinto-core/KintoID.sol";

import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";

import "forge-std/console2.sol";

/**
 * @title Renounce Upgrader Role
 * @notice This script:
 * 1. Renounces UPGRADER_ROLE from KINTO_ADMIN_MULTISIG
 */
contract DeployScript is MigrationHelper {
    // KintoAdminMultisig address
    address public constant KINTO_ADMIN_MULTISIG = 0x2e2B1c42E38f5af81771e65D87729E57ABD1337a;

    function run() public override {
        super.run();

        // Fetch deployed contracts
        AccessManager accessManager = AccessManager(_getChainDeployment("AccessManager"));

        console2.log("Starting UPGRADER_ROLE renounce script");
        console2.log("Current chain ID:", block.chainid);
        console2.log("AccessManager address:", address(accessManager));
        console2.log("KintoAdminMultisig address:", KINTO_ADMIN_MULTISIG);

        // Check if multisig has UPGRADER_ROLE
        (bool hasUpgraderRole, uint32 upgraderDelay) = accessManager.hasRole(UPGRADER_ROLE, KINTO_ADMIN_MULTISIG);
        console2.log("KintoAdminMultisig has UPGRADER_ROLE:", hasUpgraderRole);

        if (hasUpgraderRole) {
            console2.log("UPGRADER_ROLE delay:", upgraderDelay);
            console2.log("Renounce of UPGRADER_ROLE from KintoAdminMultisig");


            _handleOps(
                abi.encodeWithSelector(AccessManager.renounceRole.selector, UPGRADER_ROLE, KINTO_ADMIN_MULTISIG),
                address(accessManager)
            );

            // Verify the role was revoked
            (bool stillHasRole,) = accessManager.hasRole(UPGRADER_ROLE, KINTO_ADMIN_MULTISIG);
            console2.log("KintoAdminMultisig has UPGRADER_ROLE after revocation:", stillHasRole);
            require(!stillHasRole, "UPGRADER_ROLE revocation failed");

            console2.log("Successfully revoked UPGRADER_ROLE from KintoAdminMultisig");
        } else {
            console2.log("KintoAdminMultisig doesn't have UPGRADER_ROLE, nothing to do");
        }

        console2.log("UPGRADER_ROLE renounce script completed successfully");
    }
}
