// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Create2} from "@openzeppelin-5.0.1/contracts/utils/Create2.sol";
import {EntryPoint} from "@aa/core/EntryPoint.sol";

import {UpgradeableBeacon} from "@openzeppelin-5.0.1/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {AccessRegistry} from "../../src/access/AccessRegistry.sol";
import {AccessPoint} from "../../src/access/AccessPoint.sol";
import {IAccessPoint} from "../../src/interfaces/IAccessPoint.sol";
import {IAccessRegistry} from "../../src/interfaces/IAccessRegistry.sol";

import "../../test/helpers/Create2Helper.sol";
import "../../test/helpers/ArtifactsReader.sol";
import "../../test/helpers/UUPSProxy.sol";

import "forge-std/Script.sol";
import "forge-std/console.sol";

contract DeployAccessProtocolScript is ArtifactsReader {

    // Entry Point address is the same on all chains.
    address payable internal constant ENTRY_POINT = payable(0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789);

    function run() public {
        console.log("RUNNING ON CHAIN WITH ID", vm.toString(block.chainid));
        uint256 deployerPrivateKey = vm.envUint('PRIVATE_KEY');
        address deployer = vm.addr(deployerPrivateKey);
        console.log("Deployer is", deployer);
        console.log("Executing with address", msg.sender);


        vm.startBroadcast(deployerPrivateKey);

        address accessRegistryAddr = _getChainDeployment("AccessRegistry");
        if (accessRegistryAddr != address(0)) {
            console.log("Already Access Registry", accessRegistryAddr);
            return;
        }

        IAccessPoint dummyAccessPointImpl = new AccessPoint(EntryPoint(ENTRY_POINT), IAccessRegistry(address(0)));
        UpgradeableBeacon beacon = new UpgradeableBeacon(address(dummyAccessPointImpl), address(deployer));
        AccessRegistry accessRegistryImpl = new AccessRegistry(beacon);
        UUPSProxy accessRegistryProxy = new UUPSProxy{salt: 0}(address(accessRegistryImpl), "");

        AccessRegistry registry = AccessRegistry(address(accessRegistryProxy));
        beacon.transferOwnership(address(registry));
        IAccessPoint accessPointImpl = new AccessPoint(EntryPoint(ENTRY_POINT), registry);

        registry.initialize();
        registry.upgradeAll(accessPointImpl);

        vm.stopBroadcast();

        // Writes the addresses to a file
        console.log("Add these addresses to the artifacts file");
    }
}
