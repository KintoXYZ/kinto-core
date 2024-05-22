// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../../src/wallet/KintoWallet.sol";
import "@kinto-core-script/utils/MigrationHelper.sol";

contract KintoMigration65DeployScript is MigrationHelper {
    using ECDSAUpgradeable for bytes32;

    function run() public override {
        super.run();

        KintoWallet kintoWallet = KintoWallet(payable(_getChainDeployment("KintoWallet-admin")));

        address[] memory apps = new address[](1);
        bool[] memory flags = new bool[](1);
        bytes memory selectorAndParams = abi.encodeWithSelector(KintoWallet.whitelistApp.selector, apps, flags);
        _handleOps(selectorAndParams, address(kintoWallet), deployerPrivateKey, "trezor");
    }
}
