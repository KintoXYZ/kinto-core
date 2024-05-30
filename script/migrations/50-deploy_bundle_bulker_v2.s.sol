// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import {BundleBulker} from "../../src/inflators/BundleBulker.sol";
import "forge-std/console2.sol";

contract KintoMigration50DeployScript is MigrationHelper {
    function run() public override {
        super.run();

        // deploy BundleBulker
        bytes memory bytecode =
            abi.encodePacked(type(BundleBulker).creationCode, abi.encode(_getChainDeployment("EntryPoint")));
        vm.broadcast(deployerPrivateKey);
        BundleBulker bundleBulker = BundleBulker(factory.deployContract(msg.sender, 0, bytecode, bytes32(0)));
        console2.log("BundleBulker deployed @", address(bundleBulker));
        require(address(bundleBulker.entryPoint()) == _getChainDeployment("EntryPoint"), "EntryPoint not set correctly");

        // TODO: whitelist BundleBulker on GETH
    }
}
