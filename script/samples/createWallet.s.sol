// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@aa/core/EntryPoint.sol";

import "../../src/KintoID.sol";
import "@kinto-core-script/utils/MigrationHelper.sol";

import "forge-std/console.sol";
import "forge-std/Script.sol";

/// @notice This script creates a Kinto Wallet (smart account) through the factory.
/// @dev It won't create a new wallet if it already exists.
contract KintoCreateWalletScript is MigrationHelper {
    KintoID _kintoID;
    EntryPoint _entryPoint;
    KintoWalletFactory _walletFactory;

    function setUp() public {}

    function run() public override {
        uint256 recipientKey = vm.envUint("TEST_PRIVATE_KEY");
        address recipientWallet = vm.rememberKey(recipientKey);
        console.log("Deployer is", vm.addr(deployerPrivateKey));
        console.log("Recipient wallet is", recipientWallet);

        uint256 totalWalletsCreated = _walletFactory.totalWallets();
        console.log("Recipient wallet is KYC'd:", _kintoID.isKYC(recipientWallet));
        if (!_kintoID.isKYC(recipientWallet)) {
            KintoID.SignatureData memory sigdata =
                _auxCreateSignature(_kintoID, recipientWallet, recipientKey, block.timestamp + 50000);
            uint16[] memory traits = new uint16[](0);
            // NOTE: must be called from KYC_PROVIDER_ROLE
            console.log("Sender has KYC_PROVIDER_ROLE:", _kintoID.hasRole(_kintoID.KYC_PROVIDER_ROLE(), msg.sender));
            vm.broadcast(deployerPrivateKey);
            _kintoID.mintIndividualKyc(sigdata, traits);
        }
        console.log("This factory has", totalWalletsCreated, "created");

        bytes32 salt = 0;
        address newWallet = _walletFactory.getAddress(recipientWallet, recipientWallet, salt);
        if (isContract(newWallet)) {
            console.log("Wallet already deployed for owner", recipientWallet, "at", newWallet);
        } else {
            vm.broadcast(deployerPrivateKey);
            address ikw = address(_walletFactory.createAccount(recipientWallet, recipientWallet, salt));
            console.log("Created wallet", ikw);
            console.log("Total Wallets:", _walletFactory.totalWallets());
        }
    }
}
