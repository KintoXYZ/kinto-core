// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {EntryPoint} from "@aa/core/EntryPoint.sol";

import {UpgradeableBeacon} from "@openzeppelin-5.0.1/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {AccessRegistry} from "../../src/access/AccessRegistry.sol";
import {AccessPoint} from "../../src/access/AccessPoint.sol";
import {IAccessPoint} from "../../src/interfaces/IAccessPoint.sol";
import {IAccessRegistry} from "../../src/interfaces/IAccessRegistry.sol";
import {WithdrawWorkflow} from "../../src/access/workflows/WithdrawWorkflow.sol";
import {WethWorkflow} from "../../src/access/workflows/WethWorkflow.sol";
import {SwapWorkflow} from "../../src/access/workflows/SwapWorkflow.sol";
import {SafeBeaconProxy} from "../../src/proxy/SafeBeaconProxy.sol";

import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import {ArtifactsReader} from "../../test/helpers/ArtifactsReader.sol";
import {UUPSProxy} from "../../test/helpers/UUPSProxy.sol";

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

contract DeployAccessProtocolScript is Script, MigrationHelper {
    // Entry Point address is the same on all chains.
    address payable internal constant ENTRY_POINT = payable(0x0000000071727De22E5E9d8BAf0edAc6f37da032);
    // Exchange Proxy address is the same on all chains.
    address internal constant EXCHANGE_PROXY = 0xDef1C0ded9bec7F1a1670819833240f027b25EfF;

    AccessRegistry registry;
    UpgradeableBeacon beacon;
    WithdrawWorkflow withdrawWorkflow;
    WethWorkflow wethWorkflow;
    SwapWorkflow swapWorkflow;

    function run() public override {
        super.run();

        address accessRegistryAddr = _getChainDeployment("AccessRegistry");
        if (accessRegistryAddr != address(0)) {
            console2.log("Access Protocol is already deployed:", accessRegistryAddr);
            return;
        }

        address dummyAccessPointImpl =
            create2(abi.encodePacked(type(AccessPoint).creationCode, abi.encode(ENTRY_POINT, address(0))));
        beacon = UpgradeableBeacon(
            create2(
                abi.encodePacked(
                    type(UpgradeableBeacon).creationCode, abi.encode(dummyAccessPointImpl, address(deployer))
                )
            )
        );
        address accessRegistryImpl = create2(abi.encodePacked(type(AccessRegistry).creationCode, abi.encode(beacon)));
        // salt to get a nice address for the registry
        address accessRegistryProxy = create2(
            abi.encodePacked(type(UUPSProxy).creationCode, abi.encode(accessRegistryImpl, "")),
            0x8bfc284f7f8858599004b8c4dd784dc4134a9128417ed118d6d482209eb26d31
        );

        registry = AccessRegistry(address(accessRegistryProxy));
        UpgradeableBeacon(beacon).transferOwnership(address(registry));
        address accessPointImpl =
            create2(abi.encodePacked(type(AccessPoint).creationCode, abi.encode(ENTRY_POINT, registry)));

        registry.initialize();
        registry.upgradeAll(IAccessPoint(accessPointImpl));

        // deploy SafeBeaconProxy just to verify it on chain
        SafeBeaconProxy safeBeaconProxy = new SafeBeaconProxy{salt: bytes32(abi.encodePacked(deployer))}(
            address(beacon), abi.encodeCall(IAccessPoint.initialize, (deployer))
        );
        console2.log("SafeBeaconProxy at: %s", address(safeBeaconProxy));

        withdrawWorkflow = WithdrawWorkflow(create2(abi.encodePacked(type(WithdrawWorkflow).creationCode)));
        registry.allowWorkflow(address(withdrawWorkflow));

        wethWorkflow = WethWorkflow(
            create2(abi.encodePacked(type(WethWorkflow).creationCode, abi.encode(getWethByChainId(block.chainid))))
        );
        registry.allowWorkflow(address(wethWorkflow));

        swapWorkflow =
            SwapWorkflow(create2(abi.encodePacked(type(SwapWorkflow).creationCode, abi.encode(EXCHANGE_PROXY))));
        registry.allowWorkflow(address(swapWorkflow));

        require(registry.beacon() == beacon, "Beacon is not set properly");
        require(registry.isWorkflowAllowed(address(withdrawWorkflow)), "Workflow is not set properly");
        require(registry.isWorkflowAllowed(address(wethWorkflow)), "Workflow is not set properly");
        require(registry.isWorkflowAllowed(address(swapWorkflow)), "Workflow is not set properly");
    }
}
