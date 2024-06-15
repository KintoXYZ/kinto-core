// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../../src/wallet/KintoWallet.sol";
import "../../src/wallet/KintoWalletFactory.sol";

import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";

contract KintoMigration74DeployScript is MigrationHelper {
    function run() public override {
        super.run();
        bytes memory bytecode;
        address implementation;

        bytecode = abi.encodePacked(
            type(KintoWallet).creationCode,
            abi.encode(
                _getChainDeployment("EntryPoint"),
                _getChainDeployment("KintoID"),
                _getChainDeployment("KintoAppRegistry")
            )
        );
        implementation = _deployImplementationAndUpgrade("KintoWallet", "V22", bytecode);

        // bytecode = abi.encodePacked(type(KintoWalletFactory).creationCode, abi.encode(implementation));
        // _deployImplementationAndUpgrade("KintoWalletFactory", "V16", bytecode);
    }
}
