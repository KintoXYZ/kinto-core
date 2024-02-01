// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "../../src/viewers/KYCViewer.sol";
import "./utils/MigrationHelper.sol";

contract KintoMigration24DeployScript is MigrationHelper {
    using ECDSAUpgradeable for bytes32;

    function run() public override {
        super.run();

        // upgrade KintoID to V5
        bytes memory bytecode = abi.encodePacked(type(KintoID).creationCode, abi.encode(""));
        deployAndUpgrade("KintoID", "V5", bytecode);

        // upgrade KintoWallet to V5
        bytecode = abi.encodePacked(
            type(KintoWallet).creationCode,
            abi.encode(
                _getChainDeployment("EntryPoint"),
                _getChainDeployment("KintoID"),
                _getChainDeployment("KintoAppRegistry")
            )
        );
        address _walletImplementation = deployAndUpgrade("KintoWallet", "V5", bytecode);

        // upgrade KintoWalletFactory to V8
        bytecode = abi.encodePacked(type(KintoWalletFactory).creationCode, abi.encode(_walletImplementation));
        deployAndUpgrade("KintoWalletFactory", "V8", bytecode);

        // upgrade SponsorPaymaster to V5
        bytecode = abi.encodePacked(type(SponsorPaymaster).creationCode, abi.encode(_getChainDeployment("EntryPoint")));
        deployAndUpgrade("SponsorPaymaster", "V5", bytecode);

        // upgrade KYCViewer to V3
        bytecode = abi.encodePacked(
            type(KYCViewer).creationCode,
            abi.encode(_getChainDeployment("KintoWalletFactory"), _getChainDeployment("Faucet"))
        );

        // initialise KYCViewer
        KYCViewer viewer = KYCViewer(_getChainDeployment("KYCViewer"));

        vm.broadcast(vm.envAddress("LEDGER_ADMIN"));
        viewer.initialize();

        deployAndUpgrade("KYCViewer", "V3", bytecode);
    }
}
