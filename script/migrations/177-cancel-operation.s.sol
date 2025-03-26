// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@kinto-core/interfaces/IKintoWallet.sol";

import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import {AccessManager} from "@openzeppelin-5.0.1/contracts/access/manager/AccessManager.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {stdJson} from "forge-std/StdJson.sol";
import "forge-std/Script.sol";
import "forge-std/console.sol";

/**
 * @title CancelOperationScript
 * @notice Script to cancel a scheduled operation in the AccessManager
 * @dev Cancels the operation with ID 0x0ad95e032eb7beedef43f2741b7bcef6566a6163eaa1ac1ef42441f25193096d8
 */
contract CancelOperationScript is MigrationHelper {
    using stdJson for string;

    function run() public override {
        super.run();

        // Get the AccessManager contract
        address accessManagerAddress = _getChainDeployment("AccessManager");
        require(accessManagerAddress != address(0), "AccessManager not deployed");
        AccessManager accessManager = AccessManager(accessManagerAddress);

        // Operation details for the operation to cancel
        address caller = kintoAdminWallet; // Kinto Multisig 2
        address target = accessManagerAddress; // AccessManager

        // The exact function data for the operation to cancel
        bytes memory operationData =
            hex"25c471a0000000000000000000000000000000000000000000000000783b0946b8c9d2e30000000000000000000000002e2b1c42e38f5af81771e65d87729e57abd1337a00000000000000000000000000000000000000000000000000000000000e8080";

        // Operation ID as a string, to be parsed into bytes32
        bytes32 operationId = hex"0ad95e032eb7beede43f2741b7bcef6566a6163eaa1ac1ef42441f25193096d8";

        // Verify the operation exists
        uint48 scheduledTime = accessManager.getSchedule(operationId);
        require(scheduledTime > 0, "Operation not scheduled or already executed");

        // Format timestamp as human-readable date
        uint256 timestamp = uint256(scheduledTime);
        console.log("Operation scheduled for timestamp:", timestamp);

        // Prepare cancel function call data
        bytes memory cancelCalldata =
            abi.encodeWithSelector(AccessManager.cancel.selector, caller, target, operationData);

        // Log operation details
        console.log("Cancelling operation...");
        console.log("Original caller:", caller);
        console.log("Target:", target);

        // Use _handleOps to execute the cancel function through the wallet
        uint256[] memory privKeys = new uint256[](2);
        privKeys[0] = deployerPrivateKey;
        privKeys[1] = hardwareWalletType;

        _handleOps(cancelCalldata, kintoAdminWallet, accessManagerAddress, 0, address(0), privKeys);

        // Verify cancellation was successful
        uint48 newScheduledTime = accessManager.getSchedule(operationId);
        if (newScheduledTime == 0) {
            console.log("Operation cancelled successfully!");
        } else {
            console.log(
                "WARNING: Operation may not have been cancelled. Scheduled time still exists:", newScheduledTime
            );
        }
    }
}
