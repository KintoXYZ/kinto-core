// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {LibString} from "solady/utils/LibString.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {console2} from "forge-std/console2.sol";
import "@kinto-core-test/helpers/ArrayHelpers.sol";
import {IController} from "@kinto-core/socket/IController.sol";

import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";

contract Script is MigrationHelper {
    using LibString for *;
    using Strings for string;
    using stdJson for string;
    using ArrayHelpers for *;

    function run() public override {
        super.run();

        // Socket Controller address
        address CONTROLLER = 0x3De040ef2Fbf9158BADF559C5606d7706ca72309;

        // Check current status
        console2.log("Current connector status:", IController(CONTROLLER).validConnectors(0xC249179B24A9B2B8d76a2026A49D7bb4307Ca674));
        console2.log("Current connector status:", IController(CONTROLLER).validConnectors(0xbef01d401b54C19B2bcFe93f5e55e0355fE24A73));

        // Update connector status to false
        _handleOps(
            abi.encodeWithSelector(
                IController.updateConnectorStatus.selector,
                [0xC249179B24A9B2B8d76a2026A49D7bb4307Ca674, 0xbef01d401b54C19B2bcFe93f5e55e0355fE24A73].toMemoryArray(),
                [false, false].toMemoryArray()
            ),
            CONTROLLER
        );

        // Verify the update was successful
        console2.log("New connector status:", IController(CONTROLLER).validConnectors(0xC249179B24A9B2B8d76a2026A49D7bb4307Ca674));
        console2.log("New connector status:", IController(CONTROLLER).validConnectors(0xbef01d401b54C19B2bcFe93f5e55e0355fE24A73));

        require(!IController(CONTROLLER).validConnectors(0xC249179B24A9B2B8d76a2026A49D7bb4307Ca674), "Connector status was not updated to false");
        require(!IController(CONTROLLER).validConnectors(0xbef01d401b54C19B2bcFe93f5e55e0355fE24A73), "Connector status was not updated to false");

        console2.log("Successfully updated connector status to false!");
    }
}
