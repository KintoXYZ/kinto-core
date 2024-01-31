// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "@aa/interfaces/IEntryPoint.sol";

import "../src/interfaces/IKintoWallet.sol";

import "../src/wallet/KintoWallet.sol";
import "../src/sample/Counter.sol";

import "./harness/KintoWalletHarness.sol";
import "./harness/SponsorPaymasterHarness.sol";
import "./harness/KintoAppRegistryHarness.sol";
import {UserOp} from "./helpers/UserOp.sol";
import {AATestScaffolding} from "./helpers/AATestScaffolding.sol";
import "../script/deploy.s.sol";

contract SharedSetup is UserOp, AATestScaffolding {
    Counter counter;

    uint256[] privateKeys;

    // events
    event UserOperationRevertReason(
        bytes32 indexed userOpHash, address indexed sender, uint256 nonce, bytes revertReason
    );
    event KintoWalletInitialized(IEntryPoint indexed entryPoint, address indexed owner);
    event WalletPolicyChanged(uint256 newPolicy, uint256 oldPolicy);
    event RecovererChanged(address indexed newRecoverer, address indexed recoverer);
    event PostOpRevertReason(bytes32 indexed userOpHash, address indexed sender, uint256 nonce, bytes revertReason);

    function setUp() public virtual {
        // deploy contracts using deploy script
        DeployerScript deployer = new DeployerScript();
        contracts = deployer.runAndReturnResults(_ownerPk);

        // set contracts
        _entryPoint = IKintoEntryPoint(address(contracts.entryPoint));
        _kintoAppRegistry = KintoAppRegistry(contracts.registry);
        _kintoID = KintoID(contracts.kintoID);
        _walletFactory = KintoWalletFactory(contracts.factory);
        _kintoWallet = IKintoWallet(contracts.wallet);
        _engenCredits = EngenCredits(contracts.engenCredits);
        _paymaster = SponsorPaymaster(contracts.paymaster);
        _kycViewer = KYCViewer(contracts.viewer);
        _faucet = Faucet(contracts.faucet);

        // all tests will use 1 private key (_ownerPk) unless otherwise specified
        privateKeys = new uint256[](1);
        privateKeys[0] = _ownerPk;

        // grant kyc provider role to _kycProvider on kintoID
        bytes32 role = _kintoID.KYC_PROVIDER_ROLE();
        vm.prank(_owner);
        _kintoID.grantRole(role, _kycProvider);

        // approve wallet's owner KYC
        approveKYC(_kycProvider, _owner, _ownerPk);

        // give some eth to _owner
        vm.deal(_owner, 1e20);

        // deploy latest KintoWallet version through wallet factory
        vm.prank(_owner);
        _kintoWallet = _walletFactory.createAccount(_owner, _recoverer, 0);
        fundSponsorForApp(_owner, address(_kintoWallet));

        // deploy Counter contract
        counter = new Counter();
        assertEq(counter.count(), 0);

        registerApp(_owner, "test", address(counter));
        whitelistApp(address(counter));
        fundSponsorForApp(_owner, address(counter));
    }

    function testUp() public virtual {
        assertEq(_kintoWallet.owners(0), _owner);
        assertEq(_entryPoint.walletFactory(), address(_walletFactory));
        assertEq(_kintoWallet.getOwnersCount(), 1);
    }
}
