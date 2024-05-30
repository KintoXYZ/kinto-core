// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../../src/apps/KintoAppRegistry.sol";
import "../../src/paymasters/SponsorPaymaster.sol";
import "../../src/tokens/EngenCredits.sol";
import "../../src/viewers/KYCViewer.sol";
import "../../src/wallet/KintoWallet.sol";
import "../../src/KintoID.sol";
import "../../src/wallet/KintoWalletFactory.sol";
import "../../src/Faucet.sol";

import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";

contract KintoMigration62DeployScript is MigrationHelper {
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
        implementation = _deployImplementationAndUpgrade("KintoWallet", "V8", bytecode);
    }
}
