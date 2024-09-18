// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {IEntryPoint} from "@aa-v7/interfaces/IEntryPoint.sol";
import {IBridger} from "@kinto-core/interfaces/bridger/IBridger.sol";

import {UpgradeableBeacon} from "@openzeppelin-5.0.1/contracts/proxy/beacon/UpgradeableBeacon.sol";

import {AccessRegistry} from "../../src/access/AccessRegistry.sol";
import {AccessPoint} from "../../src/access/AccessPoint.sol";
import {IAccessPoint} from "../../src/interfaces/IAccessPoint.sol";
import {IAccessRegistry} from "../../src/interfaces/IAccessRegistry.sol";
import {WithdrawWorkflow} from "../../src/access/workflows/WithdrawWorkflow.sol";
import {WethWorkflow} from "../../src/access/workflows/WethWorkflow.sol";
import {BridgeWorkflow} from "../../src/access/workflows/BridgeWorkflow.sol";
import {SwapWorkflow} from "../../src/access/workflows/SwapWorkflow.sol";
import {SafeBeaconProxy} from "../../src/proxy/SafeBeaconProxy.sol";

import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import {ArtifactsReader} from "../../test/helpers/ArtifactsReader.sol";
import {UUPSProxy} from "../../test/helpers/UUPSProxy.sol";

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

contract DeployScript is Script, MigrationHelper {
    // Entry Point address is the same on all chains.
    address payable internal constant ENTRY_POINT = payable(0x0000000071727De22E5E9d8BAf0edAc6f37da032);
    // Exchange Proxy address is the same on all chains.
    address internal constant EXCHANGE_PROXY = 0x0000000000001fF3684f28c67538d4D072C22734;

    AccessRegistry registry;
    WithdrawWorkflow withdrawWorkflow;
    WethWorkflow wethWorkflow;
    SwapWorkflow swapWorkflow;
    BridgeWorkflow bridgeWorkflow;

    function run() public override {
        super.run();

        registry = AccessRegistry(_getChainDeployment("AccessRegistry"));
        if (address(registry) == address(0)) {
            console2.log("Access Protocol has to be deployed");
            return;
        }

        address beacon = _getChainDeployment("AccessRegistryBeacon");

        vm.broadcast(deployerPrivateKey);
        address accessRegistryImpl = address(new AccessRegistry(UpgradeableBeacon(beacon)));

        vm.broadcast(deployerPrivateKey);
        registry.upgradeToAndCall(accessRegistryImpl, bytes(""));

        saveContractAddress("AccessRegistryV4-impl", accessRegistryImpl);

        vm.broadcast(deployerPrivateKey);
        AccessPoint newImpl = new AccessPoint(IEntryPoint(ENTRY_POINT), registry);

        vm.broadcast(deployerPrivateKey);
        registry.upgradeAll(newImpl);
        saveContractAddress("AccessPointV4-impl", address(newImpl));

        vm.broadcast(deployerPrivateKey);
        swapWorkflow = new SwapWorkflow((EXCHANGE_PROXY));
        saveContractAddress("SwapWorkflowV2", address(swapWorkflow));

        vm.broadcast(deployerPrivateKey);
        registry.allowWorkflow(address(swapWorkflow));

        vm.broadcast(deployerPrivateKey);
        bridgeWorkflow = new BridgeWorkflow(IBridger(_getChainDeployment("Bridger")));
        saveContractAddress("BridgeWorkflow", address(bridgeWorkflow));

        vm.broadcast(deployerPrivateKey);
        registry.allowWorkflow(address(bridgeWorkflow));

        require(address(registry.beacon()) == beacon, "Beacon is not set properly");
        require(registry.isWorkflowAllowed(address(swapWorkflow)), "Workflow is not set properly");
        require(registry.isWorkflowAllowed(address(bridgeWorkflow)), "Workflow is not set properly");
    }
}
