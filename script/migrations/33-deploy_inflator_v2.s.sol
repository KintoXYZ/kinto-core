// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../../src/inflators/KintoInflator.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract KintoMigration33DeployScript is MigrationHelper {
    function run() public override {
        super.run();

        bytes memory bytecode = abi.encodePacked(type(KintoInflator).creationCode);
        _deployImplementationAndUpgrade("KintoInflator", "V2", bytecode);

        // transfer ownership to LEDGER_ADMIN
        address inflator = _getChainDeployment("KintoInflator");
        _handleOps(
            abi.encodeWithSelector(Ownable.transferOwnership.selector, vm.envAddress("LEDGER_ADMIN")),
            inflator,
            deployerPrivateKey
        );
        assertEq(KintoInflator(inflator).owner(), vm.envAddress("LEDGER_ADMIN"));
    }
}
