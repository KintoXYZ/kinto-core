// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../../src/wallet/KintoWallet.sol";
import "@kinto-core-script/utils/MigrationHelper.sol";

contract KintoMigration65DeployScript is MigrationHelper {
    using ECDSAUpgradeable for bytes32;

    function run() public override {
        super.run();
        KintoWallet kintoWallet = KintoWallet(payable(_getChainDeployment("KintoWallet-admin")));
        KintoWalletFactory kintoWalletFactory = KintoWalletFactory(payable(_getChainDeployment("KintoWalletFactory")));

        // create wallet with hot wallet as signer
        address signer1 = kintoWallet.owners(0);
        vm.prank(signer1);
        IKintoWallet fedeWallet = kintoWalletFactory.createAccount(signer1, signer1, 0);

        // add funds to fedeWallet
        vm.prank(0x6E31039abF8d248aBed57E307C9E1b7530c269E4);
        kintoWalletFactory.sendMoneyToAccount{value: 0.1 ether}(address(fedeWallet));

        // reset signers and change policy to add trezor
        address[] memory signers = new address[](2);
        signers[0] = 0x660ad4B5A74130a4796B4d54BC6750Ae93C86e6c;
        signers[1] = 0x9f963A6Bbb236eD4924Ca499575bb95d9AB56993; // fede's trezor wallet

        bytes memory selectorAndParams = abi.encodeWithSelector(KintoWallet.resetSigners.selector, signers, 3);
        _handleOps(selectorAndParams, address(fedeWallet), address(fedeWallet), address(0), deployerPrivateKey);

        // change policy again to 1 (requires the 2 signers)
        uint256[] memory privateKeys = new uint256[](2);
        privateKeys[0] = deployerPrivateKey;
        privateKeys[1] = 1; // indicates the 2nd signer is a trezor wallet
        selectorAndParams = abi.encodeWithSelector(KintoWallet.setSignerPolicy.selector, signers, 1);
        _handleOps(selectorAndParams, address(fedeWallet), address(fedeWallet), address(0), privateKeys);
    }
}
