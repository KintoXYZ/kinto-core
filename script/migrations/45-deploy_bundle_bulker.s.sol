// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import {BundleBulker} from "../../src/inflators/BundleBulker.sol";
import "forge-std/console2.sol";

contract KintoMigration45DeployScript is MigrationHelper {
    function run() public override {
        super.run();

        // deploy BundleBulker
        bytes memory bytecode = abi.encodePacked(type(BundleBulker).creationCode);
        vm.broadcast(deployerPrivateKey);
        BundleBulker bundleBulker = BundleBulker(factory.deployContract(msg.sender, 0, bytecode, bytes32(0)));
        console2.log("BundleBulker deployed @", address(bundleBulker));

        // TODO: whitelist BundleBulker on GETH
    }
}
