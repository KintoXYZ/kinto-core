// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./utils/MigrationHelper.sol";
import {BundleBulker} from "../../src/inflators/BundleBulker.sol";

contract KintoMigration45DeployScript is MigrationHelper {
    using ECDSAUpgradeable for bytes32;

    function run() public override {
        super.run();

        // deploy BundleBulker
        bytes memory bytecode = abi.encodePacked(type(BundleBulker).creationCode);
        vm.broadcast(deployerPrivateKey);
        BundleBulker bundleBulker = BundleBulker(factory.deployContract(msg.sender, 0, bytecode, bytes32(0)));
        console.log("BundleBulker deployed @", address(bundleBulker));

        // TODO: whitelist BundleBulker on GETH
    }
}
