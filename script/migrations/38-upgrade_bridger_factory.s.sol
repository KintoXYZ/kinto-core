// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../../src/wallet/KintoWalletFactory.sol";
import "../../src/bridger/BridgerL2.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";

contract KintoMigration42DeployScript is MigrationHelper {
    function run() public override {
        super.run();

        bytes memory bytecode =
            abi.encodePacked(type(BridgerL2).creationCode, abi.encode(_getChainDeployment("KintoWalletFactory")));

        _deployImplementationAndUpgrade("BridgerL2", "V3", bytecode);

        bytecode = abi.encodePacked(
            type(KintoWalletFactory).creationCode, abi.encode(_getChainDeployment("KintoWalletV6-impl"))
        );
        _deployImplementationAndUpgrade("KintoWalletFactory", "V11", bytecode);
    }
}
