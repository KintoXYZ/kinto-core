// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../../src/wallet/KintoWalletFactory.sol";
import "../../src/wallet/KintoWallet.sol";
import "../../src/sample/Counter.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";

contract ResetWalletSignersScript is MigrationHelper {
    function run() public override {
        super.run();

        // Add a new signer
        address[] memory signers = new address[](4);
        signers[0] = IKintoWallet(kintoAdminWallet).owners(0);
        signers[1] = IKintoWallet(kintoAdminWallet).owners(1);
        signers[2] = IKintoWallet(kintoAdminWallet).owners(2);
        signers[3] = 0x94561e98DD5E55271f91A103e4979aa6C493745E;

        _handleOps(
            abi.encodeWithSelector(
                IKintoWallet.resetSigners.selector, signers, IKintoWallet(kintoAdminWallet).TWO_SIGNERS()
            ),
            kintoAdminWallet
        );

        // Make sure we still can sign
        Counter counter = Counter(_getChainDeployment("Counter"));
        _whitelistApp(_getChainDeployment("Counter"), true);
        uint256 count = counter.count();
        _handleOps(abi.encodeWithSignature("increment()"), _getChainDeployment("Counter"));
        assertEq(counter.count(), count + 1);
    }
}
