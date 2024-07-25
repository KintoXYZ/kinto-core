// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../../src/wallet/KintoWallet.sol";
import "../../src/wallet/KintoWalletFactory.sol";
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

        bytecode = abi.encodePacked(
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
        bytecode = abi.encodePacked(
            type(KintoWalletFactory).creationCode,
            abi.encode(0xC99D77eF43FCA9D491c1f5B900F74649236055C3, _getChainDeployment("KintoAppRegistry"))
        );
        impl = _deployImplementationAndUpgrade("KintoWalletFactory", "V20", bytecode);
        saveContractAddress("KintoWalletFactoryV20-impl", impl);
    }
}
