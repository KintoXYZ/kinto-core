// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@aa/interfaces/IAccount.sol";
import "@aa/interfaces/INonceManager.sol";
import "@aa/interfaces/IEntryPoint.sol";
import "@aa/core/EntryPoint.sol";
import "../../src/KintoID.sol";
import {IKintoEntryPoint} from "../../src/interfaces/IKintoEntryPoint.sol";
import {UUPSProxy} from "../helpers/UUPSProxy.sol";
import {KYCSignature} from "../helpers/KYCSignature.sol";

import "../../src/wallet/KintoWallet.sol";
import "../../src/tokens/EngenCredits.sol";
import "../../src/wallet/KintoWalletFactory.sol";
import "../../src/paymasters/SponsorPaymaster.sol";

import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "forge-std/Test.sol";
import "forge-std/console.sol";

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
    UUPSProxy _proxycredit;
    EngenCredits _engenCredits;

    function deployAAScaffolding(address _owner, uint256 _ownerPk, address _kycProvider, address _recoverer) public {
        // Deploy Kinto ID
        deployKintoID(_owner, _kycProvider);

        // vm.startPrank(_owner);
        EntryPoint entry = new EntryPoint{salt: 0}();
        _entryPoint = IKintoEntryPoint(address(entry));
        // vm.stopPrank();

        // Deploy wallet & wallet factory
        deployWalletFactory(_owner);

        // Approve wallet's owner KYC
        approveKYC(_kycProvider, _owner, _ownerPk);

        // deploy WalletV1 through wallet factory and initialize it
        vm.prank(_owner);
        _kintoWalletv1 = _walletFactory.createAccount(_owner, _recoverer, 0);

        // Deploy paymaster
        deployPaymaster(_owner);

        // Deploy Engen Credits
        deployEngenCredits(_owner);

        // Give some eth
        vm.deal(_owner, 1e20);
    }

    function _fundPaymasterForContract(address _contract) internal {
        // We add the deposit to the counter contract in the paymaster
        _paymaster.addDepositFor{value: 1e19}(address(_contract));
    }

    function deployKintoID(address _owner, address _kycProvider) public {
        vm.startPrank(_owner);
        // Deploy Kinto ID
        _implementation = new KintoID();

        // deploy _proxy contract and point it to _implementation
        _proxy = new UUPSProxy{salt: 0}(address(_implementation), "");

        // wrap in ABI to support easier calls
        _kintoIDv1 = KintoID(address(_proxy));

        // Initialize _proxy
        _kintoIDv1.initialize();
        _kintoIDv1.grantRole(_kintoIDv1.KYC_PROVIDER_ROLE(), _kycProvider);
        vm.stopPrank();
    }

    function deployWalletFactory(address _owner) public {
        vm.startPrank(_owner);

        // Deploy wallet implementation
        _kintoWalletImpl = new KintoWallet{salt: 0}(_entryPoint, _kintoIDv1);

        //Deploy wallet factory implementation
        _walletFactoryI = new KintoWalletFactory{salt: 0}(_kintoWalletImpl);
        _proxyf = new UUPSProxy{salt: 0}(address(_walletFactoryI), "");
        _walletFactory = KintoWalletFactory(address(_proxyf));

        // Initialize wallet factory
        _walletFactory.initialize(_kintoIDv1);

        // Set the wallet factory in the entry point
        _entryPoint.setWalletFactory(address(_walletFactory));

        vm.stopPrank();
    }

    function deployPaymaster(address _owner) public {
        vm.startPrank(_owner);

        // deploy the paymaster
        _paymaster = new SponsorPaymaster{salt: 0}(_entryPoint);

        // deploy _proxy contract and point it to _implementation
        _proxys = new UUPSProxy{salt: 0}(address(_paymaster), "");

        // wrap in ABI to support easier calls
        _paymaster = SponsorPaymaster(address(_proxys));

        // initialize proxy
        _paymaster.initialize(_owner);

        vm.stopPrank();
    }

    function deployEngenCredits(address _owner) public {
        vm.startPrank(_owner);

        // deploy the engen credits
        _engenCredits = new EngenCredits{salt: 0}();

        // deploy _proxy contract and point it to _implementation
        _proxycredit = new UUPSProxy{salt: 0}(address(_engenCredits), "");

        // wrap in ABI to support easier calls
        _engenCredits = EngenCredits(address(_proxycredit));

        // initialize proxy
        _engenCredits.initialize();

        vm.stopPrank();
    }

    function approveKYC(address _kycProvider, address _account, uint256 _accountPk) public {
        vm.startPrank(_kycProvider);

        IKintoID.SignatureData memory sigdata =
            _auxCreateSignature(_kintoIDv1, _account, _account, _accountPk, block.timestamp + 1000);
        uint8[] memory traits = new uint8[](0);
        _kintoIDv1.mintIndividualKyc(sigdata, traits);

        vm.stopPrank();
    }

    function approveKYC(address _kycProvider, address _account, uint256 _accountPk, uint8[] memory traits) public {
        vm.startPrank(_kycProvider);

        IKintoID.SignatureData memory sigdata =
            _auxCreateSignature(_kintoIDv1, _account, _account, _accountPk, block.timestamp + 1000);
        _kintoIDv1.mintIndividualKyc(sigdata, traits);

        vm.stopPrank();
    }

    function revokeKYC(address _kycProvider, address _account, uint256 _accountPk) public {
        vm.startPrank(_kycProvider);

        IKintoID.SignatureData memory sigdata =
            _auxCreateSignature(_kintoIDv1, _account, _account, _accountPk, block.timestamp + 1000);
        _kintoIDv1.burnKYC(sigdata);

        vm.stopPrank();
    }
}
