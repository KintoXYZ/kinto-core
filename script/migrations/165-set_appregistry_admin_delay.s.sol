// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {AccessManager} from "@openzeppelin-5.0.1/contracts/access/manager/AccessManager.sol";
import {IAccessControl} from "@openzeppelin-5.0.1/contracts/access/IAccessControl.sol";
import {KintoAppRegistry} from "@kinto-core/apps/KintoAppRegistry.sol";

import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";

import "forge-std/console2.sol";

/**
 * @title Set KintoAppRegistry Target Admin Delay Script
 * @notice This script sets the target admin delay for the KintoAppRegistry contract
 * to prevent admin from moving selectors to another role without delay
 */
contract DeployScript is MigrationHelper {
    function run() public override {
        super.run();

        // Fetch deployed contracts
        AccessManager accessManager = AccessManager(_getChainDeployment("AccessManager"));
        KintoAppRegistry appRegistry = KintoAppRegistry(_getChainDeployment("KintoAppRegistry"));

        console2.log("Setting target admin delay for KintoAppRegistry");
        console2.log("Current chain ID:", block.chainid);
        console2.log("AccessManager address:", address(accessManager));
        console2.log("KintoAppRegistry address:", address(appRegistry));
        console2.log("Admin delay to set:", UPGRADE_DELAY);

        // Get current admin delay
        uint32 currentAdminDelay = accessManager.getTargetAdminDelay(address(appRegistry));
        console2.log("Current admin delay:", currentAdminDelay);

        // Set target admin delay for KintoAppRegistry
        _handleOps(
            abi.encodeWithSelector(AccessManager.setTargetAdminDelay.selector, address(appRegistry), UPGRADE_DELAY),
            address(accessManager)
        );

        // need to warp since delay is not immediate
        vm.warp(block.timestamp + 7 days);

        // Verify the delay was updated
        uint32 newAdminDelay = accessManager.getTargetAdminDelay(address(appRegistry));
        assertEq(newAdminDelay, UPGRADE_DELAY, "Admin delay was not properly updated");
        console2.log("Successfully set admin delay for KintoAppRegistry to:", newAdminDelay);
    }
}
