// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../../src/viewers/KYCViewer.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";

contract KYCViewerV3 is KYCViewer {
    constructor(address _kintoWalletFactory, address _faucet, address _engenCredits, address _kintoAppRegistry)
        KYCViewer(_kintoWalletFactory, _faucet, _engenCredits, _kintoAppRegistry)
    {}
}

contract KintoMigration23DeployScript is MigrationHelper {
    function run() public override {
        super.run();

        // generate bytecode for KYCViewer
        bytes memory bytecode = abi.encodePacked(
            type(KYCViewerV3).creationCode,
            abi.encode(
                _getChainDeployment("KintoWalletFactory"),
                _getChainDeployment("Faucet"),
                _getChainDeployment("EngenCredits")
            )
        );

        // upgrade KYCViewer to V3
        _deployImplementationAndUpgrade("KYCViewer", "V3", bytecode);
    }
}
