// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {SafeBeaconProxy} from "@kinto-core/proxy/SafeBeaconProxy.sol";
import {Viewer} from "@kinto-core/viewers/Viewer.sol";

import {UUPSProxy} from "@kinto-core-test/helpers/UUPSProxy.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

contract DeployViewerScript is Script, MigrationHelper {
    Viewer internal viewer;

    function run() public override {
        super.run();

        address viewerAddr = _getChainDeployment("Viewer");
        if (viewerAddr != address(0)) {
            console2.log("Viewer is already deployed:", viewerAddr);
            return;
        }

        address viewerImpl = create2(abi.encodePacked(type(Viewer).creationCode));
        // salt to get a nice address for the viewer
        address viewerProxy = create2(
            abi.encodePacked(type(UUPSProxy).creationCode, abi.encode(viewerImpl, "")),
            0xdfaa1b650599cbcc41400113049359311bc10a6411c3cc13cdd1944ff916102e
        );

        viewer = Viewer(address(viewerProxy));
        viewer.initialize();

        require(viewer.getBalances(new address[](0), address(this)).length == 0, "getBalances not working");
    }
}
