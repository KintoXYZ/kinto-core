// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {AccessManager} from "@openzeppelin-5.0.1/contracts/access/manager/AccessManager.sol";
import {IAccessControl} from "@openzeppelin-5.0.1/contracts/access/IAccessControl.sol";
import {KintoAppRegistry} from "@kinto-core/apps/KintoAppRegistry.sol";
import {KintoID} from "@kinto-core/KintoID.sol";
import {KintoWalletFactory} from "@kinto-core/wallet/KintoWalletFactory.sol";

import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";

import "forge-std/console2.sol";

/**
 * @title Set Target Admin Delay for Core Contracts
 * @notice This script sets the target admin delay to 12 days for the following contracts:
 * 1. KintoAppRegistry
 * 2. KintoID
 * 3. KintoWalletFactory
 */
contract DeployScript is MigrationHelper {
    // Target admin delay to set: 12 days
    uint32 public constant TARGET_ADMIN_DELAY = 12 days;

    // AccessManager's minSetback period
    uint32 public constant MIN_SETBACK = 5 days;

    // KintoAdminMultisig address (used to execute operations)
    address public constant KINTO_ADMIN_MULTISIG = 0x2e2B1c42E38f5af81771e65D87729E57ABD1337a;

    function run() public override {
        super.run();

        // Fetch deployed contracts
        AccessManager accessManager = AccessManager(_getChainDeployment("AccessManager"));
        KintoAppRegistry appRegistry = KintoAppRegistry(_getChainDeployment("KintoAppRegistry"));
        KintoID kintoID = KintoID(_getChainDeployment("KintoID"));
        KintoWalletFactory walletFactory = KintoWalletFactory(_getChainDeployment("KintoWalletFactory"));

        console2.log("Setting target admin delay for core contracts");
        console2.log("Current chain ID:", block.chainid);
        console2.log("AccessManager address:", address(accessManager));
        console2.log("KintoAdminMultisig address:", KINTO_ADMIN_MULTISIG);
        console2.log("Target admin delay to set:", TARGET_ADMIN_DELAY);

        // Get current admin delays
        uint32 appRegistryCurrentDelay = accessManager.getTargetAdminDelay(address(appRegistry));
        uint32 kintoIDCurrentDelay = accessManager.getTargetAdminDelay(address(kintoID));
        uint32 walletFactoryCurrentDelay = accessManager.getTargetAdminDelay(address(walletFactory));

        console2.log("KintoAppRegistry current admin delay:", appRegistryCurrentDelay);
        console2.log("KintoID current admin delay:", kintoIDCurrentDelay);
        console2.log("KintoWalletFactory current admin delay:", walletFactoryCurrentDelay);

        // Set target admin delay for KintoAppRegistry
        if (appRegistryCurrentDelay != TARGET_ADMIN_DELAY) {
            console2.log("Scheduling update for KintoAppRegistry target admin delay to 12 days");

            // First schedule the operation
            bytes memory appRegistryData = abi.encodeWithSelector(
                AccessManager.setTargetAdminDelay.selector, address(appRegistry), TARGET_ADMIN_DELAY
            );

            _handleOps(
                abi.encodeWithSelector(AccessManager.schedule.selector, address(accessManager), appRegistryData, 0),
                address(accessManager)
            );

            uint48 appRegistryScheduleTime = accessManager.getSchedule(
                accessManager.hashOperation(KINTO_ADMIN_MULTISIG, address(accessManager), appRegistryData)
            );

            console2.log("KintoAppRegistry schedule time:", appRegistryScheduleTime);

            // Warp time to after the delay
            vm.warp(appRegistryScheduleTime + 1);

            // Execute the operation
            vm.prank(KINTO_ADMIN_MULTISIG);
            accessManager.execute(address(accessManager), appRegistryData);

            // minSetback is 5 days, so changes won't be immediately visible via getTargetAdminDelay
            console2.log("Waiting for minSetback period (5 days) to pass...");

            // Warp time past the minSetback period
            vm.warp(block.timestamp + MIN_SETBACK + 1);

            // Now check the delay after minSetback
            uint32 newAppRegistryDelay = accessManager.getTargetAdminDelay(address(appRegistry));
            console2.log("KintoAppRegistry updated target admin delay after minSetback:", newAppRegistryDelay);
            assertEq(
                newAppRegistryDelay, TARGET_ADMIN_DELAY, "KintoAppRegistry admin delay not effective after minSetback"
            );
        } else {
            console2.log("KintoAppRegistry target admin delay already set to", TARGET_ADMIN_DELAY);
        }

        // Set target admin delay for KintoID
        if (kintoIDCurrentDelay != TARGET_ADMIN_DELAY) {
            console2.log("Scheduling update for KintoID target admin delay to 12 days");

            // First schedule the operation
            bytes memory kintoIDData =
                abi.encodeWithSelector(AccessManager.setTargetAdminDelay.selector, address(kintoID), TARGET_ADMIN_DELAY);

            _handleOps(
                abi.encodeWithSelector(AccessManager.schedule.selector, address(accessManager), kintoIDData, 0),
                address(accessManager)
            );

            uint48 kintoIDScheduleTime = accessManager.getSchedule(
                accessManager.hashOperation(KINTO_ADMIN_MULTISIG, address(accessManager), kintoIDData)
            );

            console2.log("KintoID schedule time:", kintoIDScheduleTime);

            // Warp time to after the delay
            vm.warp(kintoIDScheduleTime + 1);

            // Execute the operation
            vm.prank(KINTO_ADMIN_MULTISIG);
            accessManager.execute(address(accessManager), kintoIDData);

            // minSetback is 5 days, so changes won't be immediately visible via getTargetAdminDelay
            console2.log("Waiting for minSetback period (5 days) to pass...");

            // Warp time past the minSetback period
            vm.warp(block.timestamp + MIN_SETBACK + 1);

            // Now check the delay after minSetback
            uint32 newKintoIDDelay = accessManager.getTargetAdminDelay(address(kintoID));
            console2.log("KintoID updated target admin delay after minSetback:", newKintoIDDelay);
            assertEq(newKintoIDDelay, TARGET_ADMIN_DELAY, "KintoID admin delay not effective after minSetback");
        } else {
            console2.log("KintoID target admin delay already set to", TARGET_ADMIN_DELAY);
        }

        // Set target admin delay for KintoWalletFactory
        if (walletFactoryCurrentDelay != TARGET_ADMIN_DELAY) {
            console2.log("Scheduling update for KintoWalletFactory target admin delay to 12 days");

            // First schedule the operation
            bytes memory walletFactoryData = abi.encodeWithSelector(
                AccessManager.setTargetAdminDelay.selector, address(walletFactory), TARGET_ADMIN_DELAY
            );

            _handleOps(
                abi.encodeWithSelector(AccessManager.schedule.selector, address(accessManager), walletFactoryData, 0),
                address(accessManager)
            );

            uint48 walletFactoryScheduleTime = accessManager.getSchedule(
                accessManager.hashOperation(KINTO_ADMIN_MULTISIG, address(accessManager), walletFactoryData)
            );

            console2.log("KintoWalletFactory schedule time:", walletFactoryScheduleTime);

            // Warp time to after the delay
            vm.warp(walletFactoryScheduleTime + 1);

            // Execute the operation
            vm.prank(KINTO_ADMIN_MULTISIG);
            accessManager.execute(address(accessManager), walletFactoryData);

            // minSetback is 5 days, so changes won't be immediately visible via getTargetAdminDelay
            console2.log("Waiting for minSetback period (5 days) to pass...");

            // Warp time past the minSetback period
            vm.warp(block.timestamp + MIN_SETBACK + 1);

            // Now check the delay after minSetback
            uint32 newWalletFactoryDelay = accessManager.getTargetAdminDelay(address(walletFactory));
            console2.log("KintoWalletFactory updated target admin delay after minSetback:", newWalletFactoryDelay);
            assertEq(
                newWalletFactoryDelay,
                TARGET_ADMIN_DELAY,
                "KintoWalletFactory admin delay not effective after minSetback"
            );
        } else {
            console2.log("KintoWalletFactory target admin delay already set to", TARGET_ADMIN_DELAY);
        }

        console2.log("Successfully set target admin delays for all contracts");
    }
}
