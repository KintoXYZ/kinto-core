// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import '@aa/core/EntryPoint.sol';
import '../../src/interfaces/IKintoID.sol';
import '../../src/wallet/KintoWalletFactory.sol';
import '../../src/paymasters/SponsorPaymaster.sol';
import '../../src/KintoID.sol';
import './Create2Helper.sol';
import './UUPSProxy.sol';
import '@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol';
import { UpgradeableBeacon } from '@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol';
import {SignatureChecker} from '@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import '@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol';

import 'forge-std/console.sol';

abstract contract AASetup is Create2Helper {
    using ECDSAUpgradeable for bytes32;
    using SignatureChecker for address;

    function _checkAccountAbstraction() internal view returns
      (KintoID _kintoIDv1,
      EntryPoint _entryPoint,
      KintoWalletFactory _walletFactory,
      SponsorPaymaster _sponsorPaymaster
    ) {
        // Kinto ID
        address kintoIDImplAddr = computeAddress(0,
            abi.encodePacked(type(KintoID).creationCode));
        address kintoProxyAddr = computeAddress(
            0, abi.encodePacked(type(UUPSProxy).creationCode,
            abi.encode(address(kintoIDImplAddr), '')));
        if (!isContract(kintoProxyAddr)) {
            console.log('Kinto ID proxy not deployed at', address(kintoProxyAddr));
            revert('Kinto ID not deployed');
        }
        _kintoIDv1 = KintoID(address(kintoProxyAddr));
        // Entry Point
        address entryPointAddr = computeAddress(0, abi.encodePacked(type(EntryPoint).creationCode));
        if (!isContract(entryPointAddr)) {
            console.log('Entry Point not deployed at', address(entryPointAddr));
            revert('Entry Point not deployed');
        }
        _entryPoint = EntryPoint(payable(entryPointAddr));

        // Wallet Implementation for the beacon
        address kintoWalletImplAddress = computeAddress(0,
            abi.encodePacked(type(KintoWallet).creationCode, abi.encode(address(_entryPoint), address(_kintoIDv1))));
        if (!isContract(kintoWalletImplAddress)) {
            console.log('Wallet impl not deployed at', address(kintoWalletImplAddress));
            revert('Wallet impl not deployed');
        }
        // Wallet Factory Impl
        address walletFImplAddr = address(0);
        if (!isContract(walletFImplAddr)) {
            console.log('Wallet Factory Impl not deployed at', address(walletFImplAddr));
            revert('Wallet Factory Impl not deployed');
        }

        // Upgradeable beacon
        address beaconAddress = address(KintoWalletFactory(walletFImplAddr).beacon());
        if (!isContract(beaconAddress)) {
            console.log('Beacon Proxy not deployed at', address(beaconAddress));
            revert('Beacon Proxy not deployed');
        }

        // Wallet Factory
        address walletFactoryAddr = computeAddress(
            0, abi.encodePacked(type(UUPSProxy).creationCode,
            abi.encode(address(walletFImplAddr), '')));
        if (!isContract(walletFactoryAddr)) {
            console.log('Wallet factory proxy not deployed at', address(walletFactoryAddr));
            revert('Wallet Factory Proxy not deployed');
        }
        _walletFactory = KintoWalletFactory(payable(walletFactoryAddr));
        // Sponsor Paymaster
        bytes memory creationCodePaymaster = abi.encodePacked(
            type(SponsorPaymaster).creationCode, abi.encode(address(_entryPoint)));
        address paymasterAddrImpl = computeAddress(0, creationCodePaymaster);
        // Check Paymaster
        if (!isContract(paymasterAddrImpl)) {
            console.log('Paymaster impl not deployed at', address(paymasterAddrImpl));
            revert('Paymaster impl not deployed');
        }
        address sponsorProxyAddr = address(0);
        if (!isContract(sponsorProxyAddr)) {
            console.log('Paymaster proxy not deployed at', address(sponsorProxyAddr));
            revert('Paymaster proxy not deployed');
        }
        _sponsorPaymaster = SponsorPaymaster(payable(sponsorProxyAddr));
    }

}