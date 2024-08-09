// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@kinto-core/interfaces/IKintoWallet.sol";

import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";

import {stdJson} from "forge-std/StdJson.sol";
import "forge-std/Script.sol";
import "forge-std/console.sol";

contract Create2Script is MigrationHelper {
    using stdJson for string;

    function run() public override {
        super.run();

        bytes32 salt = vm.envBytes32("SALT");
        bytes memory bytecode = vm.envBytes("BYTECODE");

        vm.broadcast();
        deploy(salt, bytecode);
    }
}
