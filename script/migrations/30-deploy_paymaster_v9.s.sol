// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../../src/paymasters/SponsorPaymaster.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";

contract KintoMigration30DeployScript is MigrationHelper {
    function run() public override {
        super.run();

        bytes memory bytecode =
            abi.encodePacked(type(SponsorPaymaster).creationCode, abi.encode(_getChainDeployment("EntryPoint")));
        _deployImplementationAndUpgrade("SponsorPaymaster", "V9", bytecode);
    }
}
