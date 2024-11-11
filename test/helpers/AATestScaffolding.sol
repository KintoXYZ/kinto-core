// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {StdAssertions} from "forge-std/StdAssertions.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {Vm} from "forge-std/Vm.sol";

import "@aa/core/EntryPoint.sol";
import "@openzeppelin/contracts/governance/TimelockController.sol";

import "@kinto-core/interfaces/IKintoEntryPoint.sol";

import "@kinto-core/KintoID.sol";
import "@kinto-core/apps/KintoAppRegistry.sol";
import "@kinto-core/tokens/EngenCredits.sol";
import "@kinto-core/tokens/EngenBadges.sol";
import "@kinto-core/paymasters/SponsorPaymaster.sol";
import "@kinto-core/wallet/KintoWallet.sol";
import "@kinto-core/wallet/KintoWalletFactory.sol";
import "@kinto-core/viewers/KYCViewer.sol";
import "@kinto-core/viewers/WalletViewer.sol";
import "@kinto-core/bridger/BridgerL2.sol";
import "@kinto-core/Faucet.sol";
import "@kinto-core/inflators/KintoInflator.sol";
import "@kinto-core/governance/EngenGovernance.sol";
import {BridgedKinto} from "@kinto-core/tokens/bridged/BridgedKinto.sol";

import "@kinto-core-test/helpers/UUPSProxy.sol";
import {SignatureHelper} from "@kinto-core-test/helpers/SignatureHelper.sol";
import {KintoWalletHarness} from "../harness/KintoWalletHarness.sol";
import {SponsorPaymasterHarness} from "../harness/SponsorPaymasterHarness.sol";
import {KintoAppRegistryHarness} from "../harness/KintoAppRegistryHarness.sol";

abstract contract AATestScaffolding is SignatureHelper, StdAssertions, StdCheats {
    uint256 internal constant RATE_LIMIT_PERIOD = 1 minutes;
    uint256 internal constant RATE_LIMIT_THRESHOLD = 10;
    uint256 internal constant GAS_LIMIT_PERIOD = 30 days;
    uint256 internal constant GAS_LIMIT_THRESHOLD = 0.01 ether;

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

    EngenCredits _engenCredits;
    EngenBadges _engenBadges;
    SponsorPaymaster _paymaster;
    KYCViewer _kycViewer;
    WalletViewer _walletViewer;
    Faucet _faucet;
    BridgerL2 _bridgerL2;
    KintoInflator _inflator;
    TimelockController _engenTimelock;
    EngenGovernance _engenGovernance;
    RewardsDistributor _rewardsDistributor;
    BridgedKinto _bridgedKinto;

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
    function registerApp(address _owner, string memory name, address parentContract, address[] memory devEOAs) public {
        address[] memory appContracts = new address[](0);
        uint256[4] memory appLimits = [RATE_LIMIT_PERIOD, RATE_LIMIT_THRESHOLD, GAS_LIMIT_PERIOD, GAS_LIMIT_THRESHOLD];
        registerApp(_owner, name, parentContract, appContracts, appLimits, devEOAs);
    }

    function registerApp(
        address _owner,
        string memory name,
        address parentContract,
        uint256[4] memory appLimits,
        address[] memory devEOAs
    ) public {
        address[] memory appContracts = new address[](0);
        registerApp(_owner, name, parentContract, appContracts, appLimits, devEOAs);
    }

    function registerApp(
        address _owner,
        string memory name,
        address parentContract,
        address[] memory appContracts,
        address[] memory devEOAs
    ) public {
        uint256[4] memory appLimits = [RATE_LIMIT_PERIOD, RATE_LIMIT_THRESHOLD, GAS_LIMIT_PERIOD, GAS_LIMIT_THRESHOLD];
        registerApp(_owner, name, parentContract, appContracts, appLimits, devEOAs);
    }

    // fixme: this should go through entrypoint
    function registerApp(
        address _owner,
        string memory name,
        address parentContract,
        address[] memory appContracts,
        uint256[4] memory appLimits,
        address[] memory devEOAs
    ) public {
        vm.prank(_owner);
        _kintoAppRegistry.registerApp(
            name, parentContract, appContracts, [appLimits[0], appLimits[1], appLimits[2], appLimits[3]], devEOAs
        );
    }

    function updateMetadata(
        address _owner,
        string memory name,
        address parentContract,
        address[] memory appContracts,
        address[] memory devEOAs
    ) public {
        uint256[4] memory appLimits = [RATE_LIMIT_PERIOD, RATE_LIMIT_THRESHOLD, GAS_LIMIT_PERIOD, GAS_LIMIT_THRESHOLD];
        vm.prank(_owner);
        _kintoAppRegistry.updateMetadata(name, parentContract, appContracts, appLimits, devEOAs);
    }

    function updateMetadata(
        address _owner,
        string memory name,
        address parentContract,
        uint256[4] memory appLimits,
        address[] memory devEOAs
    ) public {
        address[] memory appContracts = new address[](0);
        vm.prank(_owner);
        _kintoAppRegistry.updateMetadata(name, parentContract, appContracts, appLimits, devEOAs);
    }

    function updateMetadata(
        address _owner,
        string memory name,
        address parentContract,
        uint256[4] memory appLimits,
        address[] memory appContracts,
        address[] memory devEOAs
    ) public {
        vm.prank(_owner);
        _kintoAppRegistry.updateMetadata(name, parentContract, appContracts, appLimits, devEOAs);
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
    }

    function setSignerPolicy(uint8 policy) public {
        vm.prank(address(_kintoWallet));
        _kintoWallet.setSignerPolicy(policy);
    }

    function useHarness() public {
        KintoWalletHarness _impl = new KintoWalletHarness(_entryPoint, _kintoID, _kintoAppRegistry, _walletFactory);
        vm.prank(_walletFactory.owner());
        _walletFactory.upgradeAllWalletImplementations(_impl);

        SponsorPaymasterHarness _paymasterImpl = new SponsorPaymasterHarness(_entryPoint, _walletFactory);
        vm.prank(_paymaster.owner());
        _paymaster.upgradeTo(address(_paymasterImpl));

        KintoAppRegistryHarness _registryImpl = new KintoAppRegistryHarness(_walletFactory, _paymaster);
        vm.prank(_kintoAppRegistry.owner());
        _kintoAppRegistry.upgradeTo(address(_registryImpl));
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
}
