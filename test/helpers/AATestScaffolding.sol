// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "forge-std/StdUtils.sol";
import "forge-std/console.sol";

import "@aa/core/EntryPoint.sol";

import "../../src/interfaces/IKintoEntryPoint.sol";

import "../../src/KintoID.sol";
import "../../src/apps/KintoAppRegistry.sol";
import "../../src/tokens/EngenCredits.sol";
import "../../src/paymasters/SponsorPaymaster.sol";
import "../../src/wallet/KintoWallet.sol";
import "../../src/wallet/KintoWalletFactory.sol";
import "../../src/viewers/KYCViewer.sol";
import "../../src/Faucet.sol";

import "../helpers/UUPSProxy.sol";
import "../helpers/KYCSignature.sol";
import {KintoWalletHarness} from "../harness/KintoWalletHarness.sol";
import {SponsorPaymasterHarness} from "../harness/SponsorPaymasterHarness.sol";
import {KintoAppRegistryHarness} from "../harness/KintoAppRegistryHarness.sol";
import "../../script/deploy.s.sol";

abstract contract AATestScaffolding is KYCSignature {
    DeployerScript.DeployedContracts contracts;

    IKintoEntryPoint _entryPoint;

    // Kinto Registry
    KintoAppRegistry _kintoAppRegistry;

    // Kinto ID
    KintoID _implementation;
    KintoID _kintoID;

    // Wallet & Factory
    KintoWalletFactory _walletFactory;
    KintoWallet _kintoWalletImpl;
    IKintoWallet _kintoWallet;

    // Others
    EngenCredits _engenCredits;
    SponsorPaymaster _paymaster;
    KYCViewer _kycViewer;
    Faucet _faucet;

    /* ============ convenience methods ============ */

    function fundSponsorForApp(address _sender, address _contract) internal {
        // we add the deposit to the counter contract in the paymaster
        vm.prank(_sender);
        _paymaster.addDepositFor{value: 2 ether}(address(_contract));
    }

    function approveKYC(address _kycProvider, address _account, uint256 _accountPk) public {
        vm.startPrank(_kycProvider);

        IKintoID.SignatureData memory sigdata =
            _auxCreateSignature(_kintoID, _account, _accountPk, block.timestamp + 1000);
        uint16[] memory traits = new uint16[](0);
        _kintoID.mintIndividualKyc(sigdata, traits);

        vm.stopPrank();
    }

    function approveKYC(address _kycProvider, address _account, uint256 _accountPk, uint16[] memory traits) public {
        vm.startPrank(_kycProvider);

        IKintoID.SignatureData memory sigdata =
            _auxCreateSignature(_kintoID, _account, _accountPk, block.timestamp + 1000);
        _kintoID.mintIndividualKyc(sigdata, traits);

        vm.stopPrank();
    }

    function revokeKYC(address _kycProvider, address _account, uint256 _accountPk) public {
        vm.startPrank(_kycProvider);

        IKintoID.SignatureData memory sigdata =
            _auxCreateSignature(_kintoID, _account, _accountPk, block.timestamp + 1000);
        _kintoID.burnKYC(sigdata);

        vm.stopPrank();
    }

    // register app helpers
    // fixme: these should go through entrypoint
    function registerApp(address _owner, string memory name, address parentContract) public {
        address[] memory appContracts = new address[](0);
        uint256[4] memory appLimits = [
            _kintoAppRegistry.RATE_LIMIT_PERIOD(),
            _kintoAppRegistry.RATE_LIMIT_THRESHOLD(),
            _kintoAppRegistry.GAS_LIMIT_PERIOD(),
            _kintoAppRegistry.GAS_LIMIT_THRESHOLD()
        ];
        registerApp(_owner, name, parentContract, appContracts, appLimits);
    }

    function registerApp(address _owner, string memory name, address parentContract, uint256[4] memory appLimits)
        public
    {
        address[] memory appContracts = new address[](0);
        registerApp(_owner, name, parentContract, appContracts, appLimits);
    }

    function registerApp(address _owner, string memory name, address parentContract, address[] memory appContracts)
        public
    {
        uint256[4] memory appLimits = [
            _kintoAppRegistry.RATE_LIMIT_PERIOD(),
            _kintoAppRegistry.RATE_LIMIT_THRESHOLD(),
            _kintoAppRegistry.GAS_LIMIT_PERIOD(),
            _kintoAppRegistry.GAS_LIMIT_THRESHOLD()
        ];
        registerApp(_owner, name, parentContract, appContracts, appLimits);
    }

    // fixme: this should go through entrypoint
    function registerApp(
        address _owner,
        string memory name,
        address parentContract,
        address[] memory appContracts,
        uint256[4] memory appLimits
    ) public {
        vm.prank(_owner);
        _kintoAppRegistry.registerApp(
            name, parentContract, appContracts, [appLimits[0], appLimits[1], appLimits[2], appLimits[3]]
        );
    }

    function updateMetadata(address _owner, string memory name, address parentContract, address[] memory appContracts)
        public
    {
        uint256[4] memory appLimits = [
            _kintoAppRegistry.RATE_LIMIT_PERIOD(),
            _kintoAppRegistry.RATE_LIMIT_THRESHOLD(),
            _kintoAppRegistry.GAS_LIMIT_PERIOD(),
            _kintoAppRegistry.GAS_LIMIT_THRESHOLD()
        ];
        vm.prank(_owner);
        _kintoAppRegistry.updateMetadata(name, parentContract, appContracts, appLimits);
    }

    function updateMetadata(address _owner, string memory name, address parentContract, uint256[4] memory appLimits)
        public
    {
        address[] memory appContracts = new address[](0);
        vm.prank(_owner);
        _kintoAppRegistry.updateMetadata(name, parentContract, appContracts, appLimits);
    }

    function updateMetadata(
        address _owner,
        string memory name,
        address parentContract,
        uint256[4] memory appLimits,
        address[] memory appContracts
    ) public {
        vm.prank(_owner);
        _kintoAppRegistry.updateMetadata(name, parentContract, appContracts, appLimits);
    }

    function setSponsoredContracts(address _owner, address _app, address[] memory _contracts, bool[] memory _sponsored)
        public
    {
        vm.prank(_owner);
        _kintoAppRegistry.setSponsoredContracts(_app, _contracts, _sponsored);
    }

    function whitelistApp(address app) public {
        whitelistApp(app, true);
    }

    function whitelistApp(address app, bool whitelist) public {
        address[] memory targets = new address[](1);
        targets[0] = address(app);
        bool[] memory flags = new bool[](1);
        flags[0] = whitelist;
        vm.prank(address(_kintoWallet));
        _kintoWallet.whitelistApp(targets, flags);
    }

    function setAppKey(address app, address signer) public {
        vm.prank(address(_kintoWallet));
        _kintoWallet.setAppKey(app, signer);
    }

    function resetSigners(address[] memory newSigners, uint8 policy) public {
        vm.prank(address(_kintoWallet));
        _kintoWallet.resetSigners(newSigners, policy);
        assertEq(_kintoWallet.owners(0), newSigners[0]);
        assertEq(_kintoWallet.owners(1), newSigners[1]);
        assertEq(_kintoWallet.signerPolicy(), policy);
    }

    function setSignerPolicy(uint8 policy) public {
        vm.prank(address(_kintoWallet));
        _kintoWallet.setSignerPolicy(policy);
        assertEq(_kintoWallet.signerPolicy(), policy);
    }

    function useHarness() public {
        KintoWalletHarness _impl = new KintoWalletHarness(_entryPoint, _kintoID, _kintoAppRegistry);
        vm.prank(_walletFactory.owner());
        _walletFactory.upgradeAllWalletImplementations(_impl);

        SponsorPaymasterHarness _paymasterImpl = new SponsorPaymasterHarness(_entryPoint);
        vm.prank(_paymaster.owner());
        _paymaster.upgradeToAndCall(address(_paymasterImpl), bytes(""));

        KintoAppRegistryHarness _registryImpl = new KintoAppRegistryHarness(_walletFactory);
        vm.prank(_kintoAppRegistry.owner());
        _kintoAppRegistry.upgradeToAndCall(address(_registryImpl), bytes(""));
    }

    function changeWalletOwner(address _newOwner, address _kycProvider) public {
        // start recovery
        vm.prank(address(_walletFactory));
        _kintoWallet.startRecovery();

        // change recoverer to _newOwner
        vm.prank(_kintoWallet.recoverer());
        _walletFactory.changeWalletRecoverer(payable(address(_kintoWallet)), _newOwner);

        // burn old NFT
        deal(address(_kintoID), _kintoWallet.owners(0), 0);

        // pass recovery time
        vm.warp(block.timestamp + _kintoWallet.RECOVERY_TIME() + 1);

        // trigger monitor
        address[] memory users = new address[](1);
        users[0] = _newOwner;
        IKintoID.MonitorUpdateData[][] memory updates = new IKintoID.MonitorUpdateData[][](1);
        updates[0] = new IKintoID.MonitorUpdateData[](1);
        updates[0][0] = IKintoID.MonitorUpdateData(true, true, 5);

        vm.prank(_kycProvider);
        _kintoID.monitor(users, updates);

        // complete recovery
        vm.prank(address(_walletFactory));
        _kintoWallet.completeRecovery(users);
        assertEq(_kintoWallet.owners(0), _newOwner);
    }

    /* ============ assertion helper methods ============ */

    // selector reasons

    function assertRevertReasonEq(bytes4 expectedSelector) public {
        bool foundMatchingRevert = false;
        Vm.Log[] memory logs = vm.getRecordedLogs();

        for (uint256 i = 0; i < logs.length; i++) {
            // check if this is the correct event
            if (
                logs[i].topics[0] == keccak256("UserOperationRevertReason(bytes32,address,uint256,bytes)")
                    || logs[i].topics[0] == keccak256("PostOpRevertReason(bytes32,address,uint256,bytes)")
            ) {
                (, bytes memory revertReasonBytes) = abi.decode(logs[i].data, (uint256, bytes));

                // check if the revertReasonBytes match the expected selector
                if (revertReasonBytes.length >= 4) {
                    bytes4 actualSelector = bytes4(revertReasonBytes[0]) | (bytes4(revertReasonBytes[1]) >> 8)
                        | (bytes4(revertReasonBytes[2]) >> 16) | (bytes4(revertReasonBytes[3]) >> 24);

                    if (actualSelector == expectedSelector) {
                        foundMatchingRevert = true;
                        break; // exit the loop if a match is found
                    }
                }
            }
        }

        if (!foundMatchingRevert) {
            revert("Expected revert reason did not match");
        }
    }

    // string reasons

    function assertRevertReasonEq(bytes memory _reason) public {
        bytes[] memory reasons = new bytes[](1);
        reasons[0] = _reason;
        _assertRevertReasonEq(reasons);
    }

    /// @dev if 2 or more UserOperationRevertReason events are emitted
    function assertRevertReasonEq(bytes[] memory _reasons) public {
        _assertRevertReasonEq(_reasons);
    }

    function _assertRevertReasonEq(bytes[] memory _reasons) internal {
        uint256 matchingReverts = 0;
        uint256 idx = 0;
        Vm.Log[] memory logs = vm.getRecordedLogs();

        for (uint256 i = 0; i < logs.length; i++) {
            // check if this is the correct event
            if (
                logs[i].topics[0] == keccak256("UserOperationRevertReason(bytes32,address,uint256,bytes)")
                    || logs[i].topics[0] == keccak256("PostOpRevertReason(bytes32,address,uint256,bytes)")
            ) {
                (, bytes memory revertReasonBytes) = abi.decode(logs[i].data, (uint256, bytes));

                // check that the revertReasonBytes is long enough (at least 4 bytes for the selector + additional data for the message)
                if (revertReasonBytes.length >= 4) {
                    // remove the first 4 bytes (the function selector)
                    bytes memory errorBytes = new bytes(revertReasonBytes.length - 4);
                    for (uint256 j = 4; j < revertReasonBytes.length; j++) {
                        errorBytes[j - 4] = revertReasonBytes[j];
                    }
                    string memory decodedRevertReason = abi.decode(errorBytes, (string));
                    string[] memory prefixes = new string[](3);
                    prefixes[0] = "SP";
                    prefixes[1] = "KW";
                    prefixes[2] = "EC";

                    // clean revert reason & assert
                    string memory cleanRevertReason = _trimToPrefixAndRemoveTrailingNulls(decodedRevertReason, prefixes);
                    if (keccak256(abi.encodePacked(cleanRevertReason)) == keccak256(abi.encodePacked(_reasons[idx]))) {
                        matchingReverts++;
                        if (_reasons.length > 1) {
                            idx++; // if there's only one reason, we always use the same one
                        }
                    }
                }
            }
        }

        if (matchingReverts < _reasons.length) {
            revert("Expected revert reason did not match");
        }
    }

    function _trimToPrefixAndRemoveTrailingNulls(string memory revertReason, string[] memory prefixes)
        internal
        pure
        returns (string memory)
    {
        bytes memory revertBytes = bytes(revertReason);
        uint256 meaningfulLength = revertBytes.length;
        if (meaningfulLength == 0) return revertReason;

        // find the actual end of the meaningful content
        for (uint256 i = revertBytes.length - 1; i >= 0; i--) {
            if (revertBytes[i] != 0) {
                meaningfulLength = i + 1;
                break;
            }
            if (i == 0) break; // avoid underflow
        }
        // trim until one of the prefixes
        for (uint256 j = 0; j < revertBytes.length; j++) {
            for (uint256 k = 0; k < prefixes.length; k++) {
                bytes memory prefixBytes = bytes(prefixes[k]);
                if (j + prefixBytes.length <= meaningfulLength) {
                    bool matched = true;
                    for (uint256 l = 0; l < prefixBytes.length; l++) {
                        if (revertBytes[j + l] != prefixBytes[l]) {
                            matched = false;
                            break;
                        }
                    }
                    if (matched) {
                        // create a new trimmed and cleaned string
                        bytes memory trimmedBytes = new bytes(meaningfulLength - j);
                        for (uint256 m = j; m < meaningfulLength; m++) {
                            trimmedBytes[m - j] = revertBytes[m];
                        }
                        return string(trimmedBytes);
                    }
                }
            }
        }

        // if no prefix is found or no meaningful content, return the original string
        return revertReason;
    }
}
