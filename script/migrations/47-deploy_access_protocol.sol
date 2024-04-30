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

        vm.startBroadcast(deployerPrivateKey);

        address accessRegistryAddr = _getChainDeployment("AccessRegistry");
        if (accessRegistryAddr != address(0)) {
            console.log("Access Protocol is already deployed:", accessRegistryAddr);
            return;
        }

        address dummyAccessPointImpl = create2(
            "DummyAccessPoint-impl",
            abi.encodePacked(type(AccessPoint).creationCode, abi.encode(ENTRY_POINT, address(0)))
        );
        address beacon = create2(
            "AccessRegistryBeacon",
            abi.encodePacked(type(UpgradeableBeacon).creationCode, abi.encode(dummyAccessPointImpl, address(deployer)))
        );
        address accessRegistryImpl =
            create2("AccessRegistry-impl", abi.encodePacked(type(AccessRegistry).creationCode, abi.encode(beacon)));
        AccessRegistry(accessRegistryImpl).initialize();
        address accessRegistryProxy =
            create2('AccessRegistry', abi.encodePacked(type(UUPSProxy).creationCode, abi.encode(accessRegistryImpl)));

        AccessRegistry registry = AccessRegistry(address(accessRegistryProxy));
        UpgradeableBeacon(beacon).transferOwnership(address(registry));
        address accessPointImpl = create2(
            'AccessPoint-impl',
            abi.encodePacked(type(AccessPoint).creationCode, abi.encode(ENTRY_POINT, registry))
        );
        IAccessPoint(accessPointImpl).initialize(address(registry));

        registry.initialize();
        registry.upgradeAll(IAccessPoint(accessPointImpl));

        vm.stopBroadcast();
    }
}
