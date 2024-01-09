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

import {KintoWalletV3 as KintoWallet} from "../../src/wallet/KintoWallet.sol";
import "../../src/apps/KintoAppRegistry.sol";
import "../../src/tokens/EngenCredits.sol";
import {KintoWalletFactoryV2 as KintoWalletFactory} from "../../src/wallet/KintoWalletFactory.sol";
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

    KintoAppRegistry _kintoAppRegistry;

    KintoID _implementation;
    KintoID _kintoIDv1;

    // Wallet & Factory
    KintoWalletFactory _walletFactory;
    KintoWallet _kintoWalletImpl;
    IKintoWallet _kintoWallet;

    EngenCredits _engenCredits;
    SponsorPaymaster _paymaster;

    // proxies
    UUPSProxy _proxy;
    UUPSProxy _proxyFactory;
    UUPSProxy _proxyPaymaster;
    UUPSProxy _proxyCredit;
    UUPSProxy _proxyRegistry;

    function deployAAScaffolding(address _owner, uint256 _ownerPk, address _kycProvider, address _recoverer) public {
        // Deploy Kinto ID
        deployKintoID(_owner, _kycProvider);

        // Deploy Kinto App
        deployAppRegistry(_owner);

        // vm.startPrank(_owner);
        EntryPoint entry = new EntryPoint{salt: 0}();
        _entryPoint = IKintoEntryPoint(address(entry));
        // vm.stopPrank();

        // Deploy wallet & wallet factory
        deployWalletFactory(_owner);

        // Approve wallet's owner KYC
        approveKYC(_kycProvider, _owner, _ownerPk);

        // Deploy paymaster
        deployPaymaster(_owner);

        // Deploy Engen Credits
        deployEngenCredits(_owner);

        vm.prank(_owner);

        // deploy latest KintoWallet version through wallet factory and initialize it
        _kintoWallet = _walletFactory.createAccount(_owner, _recoverer, 0);
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
        _kintoWalletImpl = new KintoWallet{salt: 0}(_entryPoint, _kintoIDv1, _kintoAppRegistry);

        // Deploy wallet factory implementation
        KintoWalletFactory _implementation2 = new KintoWalletFactory{salt: 0}(_kintoWalletImpl);
        _proxyFactory = new UUPSProxy{salt: 0}(address(_implementation2), "");
        _walletFactory = KintoWalletFactory(address(_proxyFactory));

        // Initialize wallet factory
        _walletFactory.initialize(_kintoIDv1);

        // Set the wallet factory in the entry point
        _entryPoint.setWalletFactory(address(_walletFactory));
        _kintoAppRegistry.setWalletFactory(_walletFactory);

        vm.stopPrank();
    }

    function deployPaymaster(address _owner) public {
        vm.startPrank(_owner);

        // deploy the paymaster
        _paymaster = new SponsorPaymaster{salt: 0}(_entryPoint);

        // deploy _proxy contract and point it to _implementation
        _proxyPaymaster = new UUPSProxy{salt: 0}(address(_paymaster), "");

        // wrap in ABI to support easier calls
        _paymaster = SponsorPaymaster(address(_proxyPaymaster));

        // initialize proxy
        _paymaster.initialize(_owner);

        // Set the registry in the paymaster
        _paymaster.setAppRegistry(address(_kintoAppRegistry));

        vm.stopPrank();
    }

    function deployEngenCredits(address _owner) public {
        vm.startPrank(_owner);

        // deploy the engen credits
        _engenCredits = new EngenCredits{salt: 0}();

        // deploy _proxy contract and point it to _implementation
        _proxyCredit = new UUPSProxy{salt: 0}(address(_engenCredits), "");

        // wrap in ABI to support easier calls
        _engenCredits = EngenCredits(address(_proxyCredit));

        // initialize proxy
        _engenCredits.initialize();

        vm.stopPrank();
    }

    function deployAppRegistry(address _owner) public {
        vm.startPrank(_owner);

        // deploy the Kinto App registry
        _kintoAppRegistry = new KintoAppRegistry{salt: 0}();

        // deploy _proxy contract and point it to _implementation
        _proxyRegistry = new UUPSProxy{salt: 0}(address(_kintoAppRegistry), "");

        // wrap in ABI to support easier calls
        _kintoAppRegistry = KintoAppRegistry(address(_proxyRegistry));

        // initialize proxy
        _kintoAppRegistry.initialize();

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

    function registerApp(address _owner, string memory name, address parentContract, address[] memory appContracts)
        public
    {
        vm.startPrank(_owner);
        uint256[] memory appLimits = new uint256[](4);
        appLimits[0] = _kintoAppRegistry.RATE_LIMIT_PERIOD();
        appLimits[1] = _kintoAppRegistry.RATE_LIMIT_THRESHOLD();
        appLimits[2] = _kintoAppRegistry.GAS_LIMIT_PERIOD();
        appLimits[3] = _kintoAppRegistry.GAS_LIMIT_THRESHOLD();
        _kintoAppRegistry.registerApp(
            name, parentContract, appContracts, [appLimits[0], appLimits[1], appLimits[2], appLimits[3]]
        );
        vm.stopPrank();
    }

    ////// helper methods to assert the revert reason on UserOperationRevertReason events ////

    // string reasons

    function assertRevertReasonEq(bytes memory _reason) public {
        bytes[] memory reasons = new bytes[](1);
        reasons[0] = _reason;
        _assertRevertReasonEq(reasons, true);
    }

    // @dev if UserOperationRevertReason is string or bytes, we can specify it with isStringType
    function assertRevertReasonEq(bytes memory _reason, bool isStringType) public {
        bytes[] memory reasons = new bytes[](1);
        reasons[0] = _reason;
        _assertRevertReasonEq(reasons, isStringType);
    }

    // @dev if 2 or more UserOperationRevertReason events are emitted
    function assertRevertReasonEq(bytes[] memory _reasons) public {
        _assertRevertReasonEq(_reasons, true);
    }

    function _assertRevertReasonEq(bytes[] memory _reasons, bool isStringType) internal {
        uint256 idx = 0;
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = 0; i < logs.length; i++) {
            // check if this is the correct event
            if (logs[i].topics[0] == keccak256("UserOperationRevertReason(bytes32,address,uint256,bytes)")) {
                (, bytes memory revertReasonBytes) = abi.decode(logs[i].data, (uint256, bytes));

                // check that the revertReasonBytes is long enough (at least 4 bytes for the selector + additional data for the message)
                if (revertReasonBytes.length > 4) {
                    //decode the remaining bytes as a string
                    if (isStringType) {
                        // remove the first 4 bytes (the function selector)
                        bytes memory errorBytes = new bytes(revertReasonBytes.length - 4);
                        for (uint256 j = 4; j < revertReasonBytes.length; j++) {
                            errorBytes[j - 4] = revertReasonBytes[j];
                        }
                        string memory decodedRevertReason = abi.decode(errorBytes, (string));
                        // compare as strings
                        assertEq(decodedRevertReason, string(_reasons[idx]), "Revert reason does not match");
                    } else {
                        // compare as bytes
                        assertEq(revertReasonBytes, _reasons[idx], "Revert reason does not match");
                    }
                    idx++;
                } else {
                    revert("Revert reason bytes too short to decode");
                }
            }
        }
    }
}
