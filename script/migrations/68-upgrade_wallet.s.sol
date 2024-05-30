// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../../src/tokens/EngenCredits.sol";
import "../../src/wallet/KintoWallet.sol";
import "../../src/bridger/BridgerL2.sol";

import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";

contract KintoMigration68DeployScript is MigrationHelper {
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
        implementation = _deployImplementationAndUpgrade("KintoWallet", "V16", bytecode);
    }
}
