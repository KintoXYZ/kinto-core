// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../../src/viewers/KYCViewer.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";

contract DeployScript is MigrationHelper {
    function run() public override {
        super.run();

        // generate bytecode for KYCViewer
        bytes memory bytecode = abi.encodePacked(
            type(KYCViewer).creationCode,
            abi.encode(
                _getChainDeployment("KintoWalletFactory"),
                _getChainDeployment("Faucet"),
                _getChainDeployment("EngenCredits"),
                _getChainDeployment("KintoAppRegistry")
            )
        );

        address impl = _deployImplementationAndUpgrade("KYCViewer", "V14", bytecode);
        saveContractAddress("KYCViewerV14-impl", impl);
    }
}
