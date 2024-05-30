// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import "@kinto-core/interfaces/IKintoWallet.sol";

contract KintoMigration63DeployScript is MigrationHelper {
    function run() public override {
        super.run();

        address _walletAdmin = _getChainDeployment("KintoWallet-admin");

        address[] memory signers = new address[](3);
        signers[0] = 0x660ad4B5A74130a4796B4d54BC6750Ae93C86e6c;
        signers[1] = 0xc1f4D15C16A1f3555E0a5F7AeFD1e17AD4aaf40B;
        signers[2] = 0x94561e98DD5E55271f91A103e4979aa6C493745E;

        bytes memory selectorAndParams = abi.encodeWithSelector(IKintoWallet.resetSigners.selector, signers, 2);
        _handleOps(selectorAndParams, _walletAdmin, deployerPrivateKey);
    }
}
