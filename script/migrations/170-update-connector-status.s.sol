// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {LibString} from "solady/utils/LibString.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {console2} from "forge-std/console2.sol";
import "@kinto-core-test/helpers/ArrayHelpers.sol";

import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";

interface IController {
    function updateConnectorStatus(address[] calldata connectors, bool[] calldata statuses) external;
    function validConnectors(address connector) external view returns (bool);
}

contract Script is MigrationHelper {
    using LibString for *;
    using Strings for string;
    using stdJson for string;
    using ArrayHelpers for *;

    function run() public override {
        super.run();

        // Socket Controller address
        address CONTROLLER = 0xE1857425c14afe4142cE4df1eCb3439f194d5D1b;
        // Connector to disable
        address CONNECTOR = 0x0bf0dcEfa8d7E31d18cEf882A74499FA277F088C;

        // Check current status
        bool currentStatus = IController(CONTROLLER).validConnectors(CONNECTOR);
        console2.log("Current connector status:", currentStatus);

        // Update connector status to false
        _handleOps(
            abi.encodeWithSelector(IController.updateConnectorStatus.selector, [CONNECTOR].toMemoryArray(), [false].toMemoryArray()),
            CONTROLLER,
            deployerPrivateKey
        );

        // Verify the update was successful
        bool newStatus = IController(CONTROLLER).validConnectors(CONNECTOR);
        console2.log("New connector status:", newStatus);

        require(newStatus == false, "Connector status was not updated to false");
        console2.log("Successfully updated connector status to false!");
    }
}
