// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../../src/wallet/KintoWalletFactory.sol";
import "../../src/wallet/KintoWallet.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";

contract UpgradeWalletDeployScript is MigrationHelper {
    function run() public override {
        super.run();

        bytes memory bytecode;

        bytecode = abi.encodePacked(
            type(KintoWallet).creationCode,
            abi.encode(
                _getChainDeployment("EntryPoint"),
                _getChainDeployment("KintoID"),
                _getChainDeployment("KintoAppRegistry")
            )
        );

        replaceOwner(IKintoWallet(kintoAdminWallet), 0x4632F4120DC68F225e7d24d973Ee57478389e9Fd);
        hardwareWalletType = 1;

        address impl = _deployImplementationAndUpgrade("KintoWallet", "V27", bytecode);

        saveContractAddress("KintoWalletV27-impl", impl);
    }
}
