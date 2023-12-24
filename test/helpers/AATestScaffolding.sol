// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import '@aa/interfaces/IAccount.sol';
import '@aa/interfaces/INonceManager.sol';
import '@aa/interfaces/IEntryPoint.sol';
import '@aa/core/EntryPoint.sol';
import '../../src/KintoID.sol';
import { IKintoEntryPoint } from '../../src/interfaces/IKintoEntryPoint.sol';
import {UUPSProxy} from '../helpers/UUPSProxy.sol';
import {KYCSignature} from '../helpers/KYCSignature.sol';

import '../../src/wallet/KintoWallet.sol';
import '../../src/wallet/KintoWalletFactory.sol';
import '../../src/paymasters/SponsorPaymaster.sol';

import '@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol';
import { UpgradeableBeacon } from '@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol';
import {SignatureChecker} from '@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import '@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol';

import 'forge-std/Test.sol';
import 'forge-std/console.sol';

abstract contract AATestScaffolding is KYCSignature {
    using ECDSAUpgradeable for bytes32;
    using SignatureChecker for address;

    IKintoEntryPoint _entryPoint;
    KintoWalletFactory _walletFactoryI;
    KintoWalletFactory _walletFactory;
    KintoID _implementation;
    KintoID _kintoIDv1;
    SponsorPaymaster _paymaster;

    KintoWallet _kintoWalletImpl;
    IKintoWallet _kintoWalletv1;
    UUPSProxy _proxy;
    UUPSProxy _proxyf;
    UUPSProxy _proxys;
    UpgradeableBeacon _beacon;


  function deployAAScaffolding(address _owner, address _kycProvider, address _recoverer) public {
    vm.startPrank(_owner);
    // Deploy Kinto ID
    _implementation = new KintoID();
    // deploy _proxy contract and point it to _implementation
    _proxy = new UUPSProxy{salt: 0}(address(_implementation), '');
    // wrap in ABI to support easier calls
    _kintoIDv1 = KintoID(address(_proxy));
    // Initialize _proxy
    _kintoIDv1.initialize();
    _kintoIDv1.grantRole(_kintoIDv1.KYC_PROVIDER_ROLE(), _kycProvider);
    EntryPoint entry = new EntryPoint{salt: 0}();
    _entryPoint = IKintoEntryPoint(address(entry));
    // Deploy wallet implementation
    _kintoWalletImpl = new KintoWallet{salt: 0}(_entryPoint, _kintoIDv1);
    // Deploy beacon
    _beacon = new UpgradeableBeacon(address(_kintoWalletImpl));
    //Deploy wallet factory implementation
    _walletFactoryI = new KintoWalletFactory{salt: 0}(KintoWallet(payable(_kintoWalletImpl)));
    _proxyf = new UUPSProxy{salt: 0}(address(_walletFactoryI), '');
    _walletFactory = KintoWalletFactory(address(_proxyf));
    // Initialize wallet factory
    _walletFactory.initialize(_kintoIDv1);
    // Set the wallet factory in the entry point
    _entryPoint.setWalletFactory(address(_walletFactory));
    _entryPoint.setBeneficiary(_owner, true);
    // Mint an nft to the owner
    IKintoID.SignatureData memory sigdata = _auxCreateSignature(
        _kintoIDv1, _owner, _owner, 1, block.timestamp + 1000);
    uint16[] memory traits = new uint16[](0);
    vm.startPrank(_kycProvider);
    _kintoIDv1.mintIndividualKyc(sigdata, traits);
    vm.stopPrank();
    vm.startPrank(_owner);
    // deploy walletv1 through wallet factory and initializes it
    _kintoWalletv1 = _walletFactory.createAccount(_owner, _recoverer, 0);
    // deploy the paymaster
    _paymaster = new SponsorPaymaster{salt: 0}(_entryPoint);
    // deploy _proxy contract and point it to _implementation
    _proxys = new UUPSProxy(address(_paymaster), '');
    // wrap in ABI to support easier calls
    _paymaster = SponsorPaymaster(address(_proxys));
    // Initialize proxy
    _paymaster.initialize(_owner);
    vm.stopPrank();
  }


}
