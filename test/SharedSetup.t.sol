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
import "./helpers/UserOp.sol";
import "./helpers/AATestScaffolding.sol";
import "./helpers/ArtifactsReader.sol";
import "../script/deploy.s.sol";

contract SharedSetup is UserOp, AATestScaffolding, ArtifactsReader {
    uint256 mainnetFork;
    uint256[] privateKeys;
    Counter counter;

    // events
    event UserOperationRevertReason(
        bytes32 indexed userOpHash, address indexed sender, uint256 nonce, bytes revertReason
    );
    event KintoWalletInitialized(IEntryPoint indexed entryPoint, address indexed owner);
    event WalletPolicyChanged(uint256 newPolicy, uint256 oldPolicy);
    event RecovererChanged(address indexed newRecoverer, address indexed recoverer);
    event PostOpRevertReason(bytes32 indexed userOpHash, address indexed sender, uint256 nonce, bytes revertReason);

    function setUp() public virtual {
        // all tests will use 1 private key (_ownerPk) unless otherwise specified
        privateKeys = new uint256[](1);
        privateKeys[0] = _ownerPk;

        // if (keccak256(bytes(vm.envString("KINTO_RPC_URL"))) != keccak256(bytes(""))) {
        console.log("Running tests against a forked mainnet");
        // run tests against a forked mainnet
        // mainnetFork = vm.createFork(vm.envString("KINTO_RPC_URL"));

        // set contracts
        // _entryPoint = IKintoEntryPoint(_getChainDeployment("EntryPoint"));
        // _kintoAppRegistry = KintoAppRegistry(_getChainDeployment("KintoAppRegistry"));
        // _kintoID = KintoID(_getChainDeployment("KintoID"));
        // _walletFactory = KintoWalletFactory(_getChainDeployment("KintoWalletFactory"));
        // _kintoWallet = IKintoWallet(_getChainDeployment("KintoWallet-admin"));
        // _engenCredits = EngenCredits(_getChainDeployment("EngenCredits"));
        // _paymaster = SponsorPaymaster(_getChainDeployment("SponsorPaymaster"));
        // _kycViewer = KYCViewer(_getChainDeployment("KYCViewer"));
        // _faucet = Faucet(payable(_getChainDeployment("Faucet")));
        // } else {
        //     // deploy contracts using deploy script
        //     DeployerScript deployer = new DeployerScript();
        //     contracts = deployer.runAndReturnResults(_ownerPk);

        //     // set contracts
        //     _entryPoint = IKintoEntryPoint(address(contracts.entryPoint));
        //     _kintoAppRegistry = KintoAppRegistry(contracts.registry);
        //     _kintoID = KintoID(contracts.kintoID);
        //     _walletFactory = KintoWalletFactory(contracts.factory);
        //     _kintoWallet = IKintoWallet(contracts.wallet);
        //     _engenCredits = EngenCredits(contracts.engenCredits);
        //     _paymaster = SponsorPaymaster(contracts.paymaster);
        //     _kycViewer = KYCViewer(contracts.viewer);
        //     _faucet = Faucet(contracts.faucet);

        //     // grant kyc provider role to _kycProvider on kintoID
        //     bytes32 role = _kintoID.KYC_PROVIDER_ROLE();
        //     vm.prank(_owner);
        //     _kintoID.grantRole(role, _kycProvider);

        //     // approve wallet's owner KYC
        //     approveKYC(_kycProvider, _owner, _ownerPk);

        //     // give some eth to _owner
        //     vm.deal(_owner, 1e20);

        //     // deploy latest KintoWallet version through wallet factory
        //     vm.prank(_owner);
        //     _kintoWallet = _walletFactory.createAccount(_owner, _recoverer, 0);
        //     fundSponsorForApp(_owner, address(_kintoWallet));

        //     // deploy Counter contract
        //     counter = new Counter();
        //     assertEq(counter.count(), 0);

        //     registerApp(_owner, "test", address(counter));
        //     whitelistApp(address(counter));
        //     fundSponsorForApp(_owner, address(counter));
        // }
    }

    function testUp() public virtual {
        assertEq(_kintoWallet.owners(0), _owner);
        assertEq(_entryPoint.walletFactory(), address(_walletFactory));
        assertEq(_kintoWallet.getOwnersCount(), 1);
    }
}
