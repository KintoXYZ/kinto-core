// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../../src/inflators/KintoInflator.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract KintoMigration52DeployScript is MigrationHelper {
    function run() public override {
        super.run();

        // transfer ownership to Pimlico's address
        // NOTE: subsequent upgrades will need to be requested to Pimlico
        address inflator = _getChainDeployment("KintoInflator");
        address pimlico = 0x433704c40F80cBff02e86FD36Bc8baC5e31eB0c1;

        _handleOps(abi.encodeWithSelector(Ownable.transferOwnership.selector, pimlico), inflator, deployerPrivateKey);
        assertEq(KintoInflator(inflator).owner(), pimlico);
    }
}
