// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {EntryPoint} from "@aa/core/EntryPoint.sol";

import {UpgradeableBeacon} from "@openzeppelin-5.0.1/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {AccessRegistry} from "../../src/access/AccessRegistry.sol";
import {AccessPoint} from "../../src/access/AccessPoint.sol";
import {IAccessPoint} from "../../src/interfaces/IAccessPoint.sol";
import {IAccessRegistry} from "../../src/interfaces/IAccessRegistry.sol";

import {DeployerHelper} from "../../src/libraries/DeployerHelper.sol";
import {Create2Helper} from "../../test/helpers/Create2Helper.sol";
import {ArtifactsReader} from "../../test/helpers/ArtifactsReader.sol";
import {UUPSProxy} from "../../test/helpers/UUPSProxy.sol";

import "forge-std/Script.sol";
import "forge-std/console.sol";

contract DeployAccessProtocolScript is ArtifactsReader, DeployerHelper {
    // Entry Point address is the same on all chains.
    address payable internal constant ENTRY_POINT = payable(0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789);

    function run() public {
        console.log("RUNNING ON CHAIN WITH ID", vm.toString(block.chainid));
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        console.log("Deployer is", deployer);
        console.log("Executing with address", msg.sender);

        vm.startBroadcast(deployerPrivateKey);

        address accessRegistryAddr = _getChainDeployment("AccessRegistry");
        if (accessRegistryAddr != address(0)) {
            console.log("Already Access Registry", accessRegistryAddr);
            return;
        }

        address dummyAccessPointImpl =
            computeAddress(0, abi.encodePacked(type(AccessPoint).creationCode, abi.encode(ENTRY_POINT, address(0))));
        if (!isContract(dummyAccessPointImpl)) {
            dummyAccessPointImpl =
                address(new AccessPoint{salt: 0}(EntryPoint(ENTRY_POINT), IAccessRegistry(address(0))));
        }
        address beacon = computeAddress(
            0,
            abi.encodePacked(type(UpgradeableBeacon).creationCode, abi.encode(dummyAccessPointImpl, address(deployer)))
        );
        if (!isContract(beacon)) {
            beacon = address(new UpgradeableBeacon{salt: 0}(dummyAccessPointImpl, address(deployer)));
        }
        AccessRegistry accessRegistryImpl = new AccessRegistry{salt: 0}(UpgradeableBeacon(beacon));
        accessRegistryImpl.initialize();
        UUPSProxy accessRegistryProxy = new UUPSProxy{salt: 0}(address(accessRegistryImpl), "");

        AccessRegistry registry = AccessRegistry(address(accessRegistryProxy));
        UpgradeableBeacon(beacon).transferOwnership(address(registry));
        IAccessPoint accessPointImpl = new AccessPoint{salt: 0}(EntryPoint(ENTRY_POINT), registry);
        accessPointImpl.initialize(address(registry));

        registry.initialize();
        registry.upgradeAll(accessPointImpl);

        vm.stopBroadcast();

        // Writes the addresses to a file
        console.log("Add these addresses to the artifacts file");
    }
}
