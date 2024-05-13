// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {AccessRegistry} from "../../src/access/AccessRegistry.sol";
import {IAccessRegistry} from "../../src/interfaces/IAccessRegistry.sol";

import {DeployerHelper} from "../../src/libraries/DeployerHelper.sol";
import {ArtifactsReader} from "../../test/helpers/ArtifactsReader.sol";

import {console2} from "forge-std/console2.sol";
import {Script} from "forge-std/Script.sol";

contract UpgradeAccessProtocolScript is Script, ArtifactsReader, DeployerHelper {
    AccessRegistry registry;
    address newImpl;

    function deployContracts(address) internal override {
        registry = AccessRegistry(_getChainDeployment("AccessRegistry"));
        if (address(registry) == address(0)) {
            console2.log("Access Protocol has to be deployed");
            return;
        }

        address beacon = _getChainDeployment("AccessRegistryBeacon");

        newImpl =
            create2("AccessRegistryV3-impl", abi.encodePacked(type(AccessRegistry).creationCode, abi.encode(beacon)));

        registry.upgradeToAndCall(address(newImpl), bytes(""));
    }

    function checkContracts(address) internal view override {
        require(registry.getAddress(address(this), 1234) != address(0), "Upgrade failed");
    }
}
