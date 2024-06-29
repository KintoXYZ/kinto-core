// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../../src/wallet/KintoWalletFactory.sol";
import "../../src/wallet/KintoWallet.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";

contract KintoMigration83DeployScript is MigrationHelper {
    function run() public override {
        super.run();

        bytes memory bytecode;

        bytecode = abi.encodePacked(
            type(KintoWallet).creationCode,
            abi.encode(
                _getChainDeployment("EntryPoint"),
                _getChainDeployment("KintoID"),
                _getChainDeployment("KintoAppRegistry")
            )
        );
        _deployImplementationAndUpgrade("KintoWallet", "V23", bytecode);

        bytecode = abi.encodePacked(
            type(KintoWalletFactory).creationCode, abi.encode(_getChainDeployment("KintoWalletV23-impl"))
        );
        _deployImplementationAndUpgrade("KintoWalletFactory", "V18", bytecode);
    }
}
