// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../../src/inflators/KintoInflator.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract KintoMigration32DeployScript is MigrationHelper {
    function run() public override {
        super.run();
        address inflator = _getChainDeployment("KintoInflator");
        _handleOps(
            abi.encodeWithSelector(Ownable.transferOwnership.selector, vm.envAddress("LEDGER_ADMIN")),
            inflator,
            deployerPrivateKey
        );
        assertEq(KintoInflator(inflator).owner(), vm.envAddress("LEDGER_ADMIN"));
    }
}
