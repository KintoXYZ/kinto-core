// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../../src/wallet/KintoWallet.sol";
import "@kinto-core-script/utils/MigrationHelper.sol";
import "@kinto-core/bridger/BridgerL2.sol";

contract KintoMigration67DeployScript is MigrationHelper {
    using ECDSAUpgradeable for bytes32;

    function run() public override {
        super.run();
        KintoWallet kintoWallet = KintoWallet(payable(_getChainDeployment("KintoWallet-admin")));
        bytes memory selectorAndParams = abi.encodeWithSelector(BridgerL2.unlockCommitments.selector);
        _handleOps(selectorAndParams, address(_getChainDeployment("BridgerL2")), deployerPrivateKey, "ledger");
    }
}
