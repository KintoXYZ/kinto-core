// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../../src/viewers/KYCViewer.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";

contract KintoMigration92DeployScript is MigrationHelper {
    function run() public override {
        super.run();

        // generate bytecode for KYCViewer
        bytes memory bytecode = abi.encodePacked(
            type(KYCViewerV9).creationCode,
            abi.encode(
                _getChainDeployment("KintoWalletFactory"),
                _getChainDeployment("Faucet"),
                _getChainDeployment("EngenCredits")
            )
        );

        // upgrade KYCViewer to V9
        address impl = _deployImplementationAndUpgrade("KYCViewer", "V9", bytecode);
        saveContractAddress("KYCViewerV9-impl", impl);
    }
}
