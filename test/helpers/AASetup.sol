// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import '../../src/KintoID.sol';
import './Create2Helper.sol';
import './UUPSProxy.sol';
import '@aa/core/EntryPoint.sol';
import '../../src/interfaces/IKintoID.sol';
import '../../src/wallet/KintoWalletFactory.sol';
import '../../src/paymasters/SponsorPaymaster.sol';
import '@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol';
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
        // Wallet Factory
        address walletFactoryAddr = computeAddress(0,
            abi.encodePacked(type(KintoWalletFactory).creationCode,
            abi.encode(address(_entryPoint), address(_kintoIDv1))));
        if (!isContract(walletFactoryAddr)) {
            console.log('Wallet factory not deployed at', address(walletFactoryAddr));
            revert('Wallet Factory not deployed');
        }
        _walletFactory = KintoWalletFactory(payable(walletFactoryAddr));
        // Sponsor Paymaster
        bytes memory creationCodePaymaster = abi.encodePacked(
            type(SponsorPaymaster).creationCode, abi.encode(address(_entryPoint)));
        address paymasterAddr = computeAddress(0, creationCodePaymaster);
        // Check Paymaster
        if (!isContract(paymasterAddr)) {
            console.log('Paymaster not deployed at', address(paymasterAddr));
            revert('Paymaster not deployed');
        }
        _sponsorPaymaster = SponsorPaymaster(payable(paymasterAddr));
    }

}