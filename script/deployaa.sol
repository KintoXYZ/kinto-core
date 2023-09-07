// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/wallet/KintoWallet.sol";
import "../src/wallet/KintoWalletFactory.sol";
import "@aa/interfaces/IEntryPoint.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";
import { SignatureChecker } from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import "forge-std/console.sol";

contract KintoAAInitialDeployScript is Script {
    using ECDSAUpgradeable for bytes32;
    using SignatureChecker for address;

    IEntryPoint _entryPoint = IEntryPoint(0xB8E2e62b4d44EB2bd39d75FDF6de124b5f95F1Af);
    KintoWalletFactory _walletFactory;

    KintoWallet _kintoWalletv1;

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerPublicKey = vm.envAddress("PUBLIC_KEY");
        vm.startBroadcast(deployerPrivateKey);
        //Deploy wallet factory
        _walletFactory = new KintoWalletFactory{salt: 0}(_entryPoint);
        console.log('Wallet factory deployed at', address(_walletFactory));
        // deploy walletv1 through wallet factory and initializes it
        _kintoWalletv1 = _walletFactory.createAccount(deployerPublicKey, 0);
        console.log('wallet deployed at', address(_kintoWalletv1));
        vm.stopBroadcast();
    }
}
