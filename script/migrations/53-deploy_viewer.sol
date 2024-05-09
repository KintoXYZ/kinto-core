// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {SafeBeaconProxy} from "@kinto-core/proxy/SafeBeaconProxy.sol";
import {Viewer} from "@kinto-core/viewers/Viewer.sol";

import {DeployerHelper} from "@kinto-core/libraries/DeployerHelper.sol";
import {ArtifactsReader} from "@kinto-core-test/helpers/ArtifactsReader.sol";
import {UUPSProxy} from "@kinto-core-test/helpers/UUPSProxy.sol";

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

contract DeployViewerScript is Script, ArtifactsReader, DeployerHelper {
    Viewer internal viewer;

    function deployContracts(address) internal override {
        address viewerAddr = _getChainDeployment("Viewer");
        if (viewerAddr != address(0)) {
            console2.log("Viewer is already deployed:", viewerAddr);
            return;
        }

        address viewerImpl = create2("Viewer-impl", abi.encodePacked(type(Viewer).creationCode, ""));
        // salt to get a nice address for the viewer
        address viewerProxy = create2(
            0xdfaa1b650599cbcc41400113049359311bc10a6411c3cc13cdd1944ff916102e,
            "Viewer",
            abi.encodePacked(type(UUPSProxy).creationCode, abi.encode(viewerImpl, ""))
        );

        viewer = Viewer(address(viewerProxy));
        viewer.initialize();
    }

    function checkContracts(address) internal view override {
        require(viewer.getBalances(new address[](0), address(this)).length == 0, "getBalances not working");
    }
}
