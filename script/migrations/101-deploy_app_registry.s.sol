// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../../src/wallet/KintoWallet.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import {KintoAppRegistry} from "@kinto-core/apps/KintoAppRegistry.sol";
import "../../src/viewers/KYCViewer.sol";

contract DeployScript is MigrationHelper {
    function run() public override {
        super.run();

        bytes memory bytecode =
            abi.encodePacked(type(KintoAppRegistry).creationCode, abi.encode(_getChainDeployment("KintoWalletFactory")));
        address impl = _deployImplementationAndUpgrade("KintoAppRegistry", "V16", bytecode);

        saveContractAddress("KintoAppRegistryV16-impl", impl);

        memory bytecode = abi.encodePacked(
            type(KYCViewer).creationCode,
            abi.encode(
                _getChainDeployment("KintoWalletFactory"),
                _getChainDeployment("Faucet"),
                _getChainDeployment("EngenCredits"),
                _getChainDeployment("KintoAppRegistry")
            )
        );

        // upgrade KYCViewer to V12
        impl = _deployImplementationAndUpgrade("KYCViewer", "V12", bytecode);
        saveContractAddress("KYCViewerV12-impl", impl);
    }
}
