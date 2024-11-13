// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {SafeBeaconProxy} from "@kinto-core/proxy/SafeBeaconProxy.sol";
import {Viewer} from "@kinto-core/viewers/Viewer.sol";

import {UUPSProxy} from "@kinto-core-test/helpers/UUPSProxy.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

contract DeployViewerScript is Script, MigrationHelper {
    function run() public override {
        super.run();

        Viewer viewer = Viewer(_getChainDeployment("Viewer"));
        if (address(viewer) == address(0)) {
            console2.log("Viewer is not deployed");
            return;
        }

        vm.broadcast(deployerPrivateKey);
        address newImpl = address(new Viewer(getAavePoolProvider(), _getChainDeployment("AccessRegistry")));

        vm.broadcast(deployerPrivateKey);
        viewer.upgradeTo(newImpl);

        require(viewer.getBalances(new address[](0), address(this)).length == 0, "getBalances not working");
    }
}
