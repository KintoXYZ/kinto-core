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

        vm.startBroadcast(deployerPrivateKey);

        registry.disallowWorkflow(_getChainDeployment("AaveLendWorkflow"));
        AaveLendWorkflow aaveLendWorkflow = new AaveLendWorkflow(getAavePoolProvider());
        saveContractAddress("AaveLendWorkflow", address(aaveLendWorkflow));
        registry.allowWorkflow(address(aaveLendWorkflow));

        registry.disallowWorkflow(_getChainDeployment("AaveRepayWorkflow"));
        AaveRepayWorkflow aaveRepayWorkflow = new AaveRepayWorkflow(getAavePoolProvider());
        saveContractAddress("AaveRepayWorkflow", address(aaveRepayWorkflow));
        registry.allowWorkflow(address(aaveRepayWorkflow));

        registry.disallowWorkflow(_getChainDeployment("AaveWithdrawWorkflow"));
        AaveWithdrawWorkflow aaveWithdrawWorkflow = new AaveWithdrawWorkflow(
            getAavePoolProvider(), _getChainDeployment("Bridger"), getMamoriSafeByChainId(block.chainid)
        );
        saveContractAddress("AaveWithdrawWorkflow", address(aaveWithdrawWorkflow));
        registry.allowWorkflow(address(aaveWithdrawWorkflow));

        registry.disallowWorkflow(_getChainDeployment("AaveBorrowWorkflow"));
        AaveBorrowWorkflow aaveBorrowWorkflow =
            new AaveBorrowWorkflow(getAavePoolProvider(), _getChainDeployment("Bridger"));
        saveContractAddress("AaveBorrowWorkflow", address(aaveBorrowWorkflow));
        registry.allowWorkflow(address(aaveBorrowWorkflow));

        vm.stopBroadcast();

        require(registry.isWorkflowAllowed(address(aaveLendWorkflow)), "Workflow is not set properly");
        require(registry.isWorkflowAllowed(address(aaveRepayWorkflow)), "Workflow is not set properly");
        require(registry.isWorkflowAllowed(address(aaveWithdrawWorkflow)), "Workflow is not set properly");
        require(registry.isWorkflowAllowed(address(aaveBorrowWorkflow)), "Workflow is not set properly");
    }
}
