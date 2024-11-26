// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {AccessManager} from "@openzeppelin-5.0.1/contracts/access/manager/AccessManager.sol";

import {SafeBeaconProxy} from "@kinto-core/proxy/SafeBeaconProxy.sol";

import {UUPSProxy} from "@kinto-core-test/helpers/UUPSProxy.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

contract DeployScript is Script, MigrationHelper {
    function run() public override {
        super.run();

        if (_getChainDeployment("AccessManager") != address(0)) {
            console2.log("AccessManager is deployed");
            return;
        }

        (bytes32 salt, address expectedAddress) =
            mineSalt(keccak256(abi.encodePacked(type(AccessManager).creationCode, abi.encode(deployer))), "ACC000");

        vm.broadcast(deployerPrivateKey);
        AccessManager accessManager = new AccessManager{salt: salt}(deployer);

        assertEq(address(accessManager), address(expectedAddress));
        (bool isMember,) = accessManager.hasRole(0, deployer);
        assertTrue(isMember);

        saveContractAddress("AccessManager", address(accessManager));
    }
}
