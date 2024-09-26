// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {IEntryPoint} from "@aa-v7/interfaces/IEntryPoint.sol";
import {IBridger} from "@kinto-core/interfaces/bridger/IBridger.sol";

import {UpgradeableBeacon} from "@openzeppelin-5.0.1/contracts/proxy/beacon/UpgradeableBeacon.sol";

import {AccessRegistry} from "../../src/access/AccessRegistry.sol";
import {AccessPoint} from "../../src/access/AccessPoint.sol";
import {IAccessPoint} from "../../src/interfaces/IAccessPoint.sol";
import {IAccessRegistry} from "../../src/interfaces/IAccessRegistry.sol";
import {CrossChainSwapWorkflow} from "../../src/access/workflows/CrossChainSwapWorkflow.sol";
import {SafeBeaconProxy} from "../../src/proxy/SafeBeaconProxy.sol";

import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import {ArtifactsReader} from "../../test/helpers/ArtifactsReader.sol";
import {UUPSProxy} from "../../test/helpers/UUPSProxy.sol";

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

contract DeployScript is Script, MigrationHelper {
    function run() public override {
        super.run();

        AccessRegistry registry = AccessRegistry(_getChainDeployment("AccessRegistry"));
        if (address(registry) == address(0)) {
            console2.log("Access Protocol has to be deployed");
            return;
        }

        vm.broadcast(deployerPrivateKey);
        CrossChainSwapWorkflow crossChainSwapWorkflow =
            new CrossChainSwapWorkflow(IBridger(_getChainDeployment("Bridger")));
        saveContractAddress("CrossChainSwapWorkflowV2", address(crossChainSwapWorkflow));

        vm.broadcast(deployerPrivateKey);
        registry.allowWorkflow(address(crossChainSwapWorkflow));

        require(registry.isWorkflowAllowed(address(crossChainSwapWorkflow)), "Workflow is not set properly");
    }
}
