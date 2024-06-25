// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../../src/wallet/KintoWallet.sol";
import "../../src/viewers/WalletViewer.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";

contract KintoMigration46DeployScript is MigrationHelper {
    function run() public override {
        super.run();

        // Deploy KintoWallet
        bytes memory bytecode = abi.encodePacked(
            type(KintoWallet).creationCode,
            abi.encode(
                _getChainDeployment("EntryPoint"),
                _getChainDeployment("KintoID"),
                _getChainDeployment("KintoAppRegistry")
            )
        );
        address implementation = _deployImplementationAndUpgrade("KintoWallet", "V7", bytecode);

        // Deploy WalletViewer
        bytecode = abi.encodePacked(
            type(WalletViewer).creationCode,
            abi.encode(_getChainDeployment("KintoWalletFactory"), _getChainDeployment("KintoAppRegistry"))
        );

        implementation = _deployImplementation("WalletViewer", "V1", bytecode);
        address proxy = _deployProxy("WalletViewer", implementation);

        _whitelistApp(proxy);
        _initialize(proxy, deployerPrivateKey);
    }
}
