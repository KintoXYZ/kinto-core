// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "../../src/wallet/KintoWallet.sol";
import "./utils/MigrationHelper.sol";

contract KintoMigration22DeployScript is MigrationHelper {
    using ECDSAUpgradeable for bytes32;

    // NOTE: this migration must be run from the ledger admin
    function run() public {
        run2();

        // generate bytecode for KintoWalletV5
        bytes memory bytecode = abi.encodePacked(
            type(KintoWalletV5).creationCode,
            abi.encode(
                _getChainDeployment("EntryPoint"),
                IKintoID(_getChainDeployment("KintoID")),
                IKintoAppRegistry(_getChainDeployment("KintoAppRegistry"))
            )
        );

        // upgrade KintoWallet to V5
        deployAndUpgrade("KintoWallet", "V5", bytecode);
    }
}
