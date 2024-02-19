// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "../../src/apps/KintoAppRegistry.sol";
import "../../src/paymasters/SponsorPaymaster.sol";
import "../../src/tokens/EngenCredits.sol";
import "../../src/viewers/KYCViewer.sol";
import "../../src/wallet/KintoWallet.sol";
import "../../src/KintoID.sol";
import "../../src/wallet/KintoWalletFactory.sol";
import "../../src/Faucet.sol";

import "./utils/MigrationHelper.sol";

contract KintoMigration30DeployScript is MigrationHelper {
    using MessageHashUtils for bytes32;

    function run() public override {
        super.run();
        bytes memory bytecode;
        address implementation;

        bytecode =
            abi.encodePacked(type(KintoAppRegistry).creationCode, abi.encode(_getChainDeployment("KintoWalletFactory")));
        _deployImplementationAndUpgrade("KintoAppRegistry", "V6", bytecode);

        bytecode = abi.encodePacked(type(SponsorPaymaster).creationCode, abi.encode(_getChainDeployment("EntryPoint")));
        _deployImplementationAndUpgrade("SponsorPaymaster", "V9", bytecode);

        bytecode = abi.encodePacked(type(EngenCredits).creationCode, abi.encode(_getChainDeployment("EngenCredits")));
        _deployImplementationAndUpgrade("EngenCredits", "V3", bytecode);

        bytecode = abi.encodePacked(
            type(KYCViewer).creationCode,
            abi.encode(_getChainDeployment("KintoWalletFactory"), _getChainDeployment("Faucet"))
        );
        _deployImplementationAndUpgrade("KYCViewer", "V5", bytecode);

        bytecode = abi.encodePacked(
            type(KintoWallet).creationCode,
            abi.encode(
                _getChainDeployment("EntryPoint"),
                _getChainDeployment("KintoID"),
                _getChainDeployment("KintoAppRegistry")
            )
        );
        implementation = _deployImplementationAndUpgrade("KintoWallet", "V6", bytecode);

        bytecode = abi.encodePacked(type(Faucet).creationCode, abi.encode(_getChainDeployment("KintoWalletFactory")));
        _deployImplementationAndUpgrade("Faucet", "V6", bytecode);

        bytecode = abi.encodePacked(type(KintoID).creationCode, abi.encode(_getChainDeployment("KintoWalletFactory")));
        _deployImplementationAndUpgrade("KintoID", "V8", bytecode);

        bytecode = abi.encodePacked(type(KintoWalletFactory).creationCode, abi.encode(implementation));
        _deployImplementationAndUpgrade("KintoWalletFactory", "V10", bytecode);
    }
}
