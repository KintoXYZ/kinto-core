// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {AccessRegistry} from "../../src/access/AccessRegistry.sol";
import {IAccessRegistry} from "../../src/interfaces/IAccessRegistry.sol";

import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";

import {console2} from "forge-std/console2.sol";
import {Script} from "forge-std/Script.sol";

contract UpgradeAccessProtocolScript is Script, MigrationHelper {
    AccessRegistry registry;
    address newImpl;

    function run() public override {
        super.run();

        registry = AccessRegistry(_getChainDeployment("AccessRegistry"));
        if (address(registry) == address(0)) {
            console2.log("Access Protocol has to be deployed");
            return;
        }

        address beacon = _getChainDeployment("AccessRegistryBeacon");

        newImpl = create2(abi.encodePacked(type(AccessRegistry).creationCode, abi.encode(beacon)));

        registry.upgradeToAndCall(address(newImpl), bytes(""));

        require(registry.getAddress(address(this), 1234) != address(0), "Upgrade failed");
    }
}
