// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "./utils/MigrationHelper.sol";
import {BundleBulker} from "../../src/inflators/BundleBulker.sol";

contract KintoMigration50DeployScript is MigrationHelper {
    using ECDSAUpgradeable for bytes32;

    function run() public override {
        super.run();

        // deploy BundleBulker
        bytes memory bytecode = abi.encodePacked(type(BundleBulker).creationCode, abi.encode(_getChainDeployment("EntryPoint")));
        vm.broadcast(deployerPrivateKey);
        BundleBulker bundleBulker = BundleBulker(factory.deployContract(msg.sender, 0, bytecode, bytes32(0)));
        console.log("BundleBulker deployed @", address(bundleBulker));
        require(address(bundleBulker.entryPoint()) == _getChainDeployment("EntryPoint"), "EntryPoint not set correctly");

        // TODO: whitelist BundleBulker on GETH
    }
}
