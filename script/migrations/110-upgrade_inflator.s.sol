// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../../src/wallet/KintoWalletFactory.sol";
import "../../src/inflators/KintoInflator.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import "@kinto-core-script/migrations/const.sol";

contract Script is MigrationHelper {
    function run() public override {
        super.run();

        bytes memory bytecode = abi.encodePacked(type(KintoInflator).creationCode);

        address impl = _deployImplementationAndUpgrade("KintoInflator", "V4", bytecode);
        saveContractAddress("KintoInflatorV4-impl", impl);
    }
}
