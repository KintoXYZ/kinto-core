// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {IEntryPoint} from "@aa-v7/interfaces/IEntryPoint.sol";
import {IBridger} from "@kinto-core/interfaces/bridger/IBridger.sol";

import {UpgradeableBeacon} from "@openzeppelin-5.0.1/contracts/proxy/beacon/UpgradeableBeacon.sol";

import {AccessRegistry} from "../../src/access/AccessRegistry.sol";
import {AccessPoint} from "../../src/access/AccessPoint.sol";
import {IAccessPoint} from "../../src/interfaces/IAccessPoint.sol";
import {IAccessRegistry} from "../../src/interfaces/IAccessRegistry.sol";
import {AaveLendWorkflow} from "../../src/access/workflows/AaveLendWorkflow.sol";
import {AaveBorrowWorkflow} from "../../src/access/workflows/AaveBorrowWorkflow.sol";
import {AaveWithdrawWorkflow} from "../../src/access/workflows/AaveWithdrawWorkflow.sol";
import {AaveRepayWorkflow} from "../../src/access/workflows/AaveRepayWorkflow.sol";
import {SafeBeaconProxy} from "../../src/proxy/SafeBeaconProxy.sol";

import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import {ArtifactsReader} from "../../test/helpers/ArtifactsReader.sol";
import {UUPSProxy} from "../../test/helpers/UUPSProxy.sol";

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

contract DeployScript is Script, MigrationHelper {
    AccessRegistry registry;

    function run() public override {
        super.run();

        registry = AccessRegistry(_getChainDeployment("AccessRegistry"));
        if (address(registry) == address(0)) {
            console2.log("Access Protocol has to be deployed");
            return;
        }

        vm.broadcast(deployerPrivateKey);
        AaveLendWorkflow aaveLendWorkflow = new AaveLendWorkflow(getAavePoolProvider());
        saveContractAddress("AaveLendWorkflow", address(aaveLendWorkflow));

        vm.broadcast(deployerPrivateKey);
        registry.allowWorkflow(address(aaveLendWorkflow));

        vm.broadcast(deployerPrivateKey);
        AaveRepayWorkflow aaveRepayWorkflow = new AaveRepayWorkflow(getAavePoolProvider());
        saveContractAddress("AaveRepayWorkflow", address(aaveRepayWorkflow));

        vm.broadcast(deployerPrivateKey);
        registry.allowWorkflow(address(aaveRepayWorkflow));

        vm.broadcast(deployerPrivateKey);
        AaveWithdrawWorkflow aaveWithdrawWorkflow =
            new AaveWithdrawWorkflow(getAavePoolProvider(), _getChainDeployment("Bridger"));
        saveContractAddress("AaveWithdrawWorkflow", address(aaveWithdrawWorkflow));

        vm.broadcast(deployerPrivateKey);
        registry.allowWorkflow(address(aaveWithdrawWorkflow));

        vm.broadcast(deployerPrivateKey);
        AaveBorrowWorkflow aaveBorrowWorkflow = new AaveBorrowWorkflow(getAavePoolProvider());
        saveContractAddress("AaveBorrowWorkflow", address(aaveBorrowWorkflow));

        vm.broadcast(deployerPrivateKey);
        registry.allowWorkflow(address(aaveBorrowWorkflow));

        require(registry.isWorkflowAllowed(address(aaveLendWorkflow)), "Workflow is not set properly");
        require(registry.isWorkflowAllowed(address(aaveRepayWorkflow)), "Workflow is not set properly");
        require(registry.isWorkflowAllowed(address(aaveWithdrawWorkflow)), "Workflow is not set properly");
        require(registry.isWorkflowAllowed(address(aaveBorrowWorkflow)), "Workflow is not set properly");
    }
}
