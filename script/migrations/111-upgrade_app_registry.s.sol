// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../../src/apps/KintoAppRegistry.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";

import "forge-std/console2.sol";

contract DeployScript is MigrationHelper {
    function run() public override {
        super.run();

        bytes memory bytecode =
            abi.encodePacked(type(KintoAppRegistry).creationCode, abi.encode(_getChainDeployment("KintoWalletFactory")));
        address impl = _deployImplementationAndUpgrade("KintoAppRegistry", "V18", bytecode);
        saveContractAddress("KintoAppRegistryV18-impl", impl);
    }
}
