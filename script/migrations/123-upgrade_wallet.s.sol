// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../../src/wallet/KintoWalletFactory.sol";
import "../../src/wallet/KintoWallet.sol";
import "../../src/sample/Counter.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";

contract UpgradeWalletDeployScript is MigrationHelper {
    function run() public override {
        super.run();

        bytes memory bytecode = abi.encodePacked(
            type(KintoWallet).creationCode,
            abi.encode(
                _getChainDeployment("EntryPoint"),
                _getChainDeployment("KintoID"),
                _getChainDeployment("KintoAppRegistry"),
                _getChainDeployment("KintoWalletFactory")
            )
        );

        address impl = _deployImplementationAndUpgrade("KintoWallet", "V32", bytecode);

        saveContractAddress("KintoWalletV32-impl", impl);
    }
}
