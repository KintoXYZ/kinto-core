// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@aa/interfaces/IEntryPoint.sol";

import "@kinto-core/interfaces/IKintoWallet.sol";

import "@kinto-core/wallet/KintoWallet.sol";
import "@kinto-core/sample/Counter.sol";

import "@kinto-core-test/harness/KintoWalletHarness.sol";
import "@kinto-core-test/harness/SponsorPaymasterHarness.sol";
import "@kinto-core-test/harness/KintoAppRegistryHarness.sol";
import "@kinto-core-test/helpers/UserOp.sol";
import "@kinto-core-test/helpers/AATestScaffolding.sol";
import "@kinto-core-test/helpers/ArtifactsReader.sol";
import {ForkTest} from "@kinto-core-test/helpers/ForkTest.sol";

// scripts & migrations
import "@kinto-core-script/actions/deploy.s.sol";

abstract contract SharedSetup is ForkTest, UserOp, AATestScaffolding, ArtifactsReader {
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
    event AppKeyCreated(address indexed appKey, address indexed signer);

    function setUp() public virtual override {
        super.setUp();
        // all tests will use 1 private key (_ownerPk) unless otherwise specified
        privateKeys = new uint256[](1);
        privateKeys[0] = _ownerPk;

        deployCounter();
    }

    function setUpChain() public virtual override {
        setUpKintoLocal();
    }

    function testUp() public virtual override {}

    function labelAddresses() public virtual override {
        // label addresses
        vm.label(address(_entryPoint), "EntryPoint");
        vm.label(address(_kintoAppRegistry), "KintoAppRegistry");
        vm.label(address(_kintoID), "KintoID");
        vm.label(address(_walletFactory), "KintoWalletFactory");
        vm.label(address(_kintoWallet), "KintoWallet");
        vm.label(address(_engenCredits), "EngenCredits");
        vm.label(address(_engenBadges), "EngenBadges");
        vm.label(address(_paymaster), "SponsorPaymaster");
        vm.label(address(_kycViewer), "KYCViewer");
        vm.label(address(_faucet), "Faucet");
        vm.label(address(_bridgerL2), "BridgerL2");
        vm.label(address(_engenGovernance), "EngenGovernance");
    }

    function deployCounter() public {
        // deploy Counter contract
        counter = new Counter();
        assertEq(counter.count(), 0);

        registerApp(_owner, "test", address(counter));
        whitelistApp(address(counter));
        fundSponsorForApp(_owner, address(counter));
    }

    function setUpKintoLocal() public {
        // Deal ETH to _owner
        vm.deal(_owner, 1e20);

        // deploy contracts using deploy script
        DeployerScript deployer = new DeployerScript();

        DeployerScript.DeployedContracts memory contracts = deployer.runAndReturnResults(_ownerPk);
        // set contracts
        _entryPoint = IKintoEntryPoint(address(contracts.entryPoint));
        _kintoAppRegistry = KintoAppRegistry(contracts.registry);
        _kintoID = KintoID(contracts.kintoID);
        _walletFactory = KintoWalletFactory(contracts.factory);
        _kintoWallet = IKintoWallet(contracts.wallet);
        _engenCredits = EngenCredits(contracts.engenCredits);
        _engenBadges = EngenBadges(contracts.engenBadges);
        _paymaster = SponsorPaymaster(contracts.paymaster);
        _kycViewer = KYCViewer(contracts.viewer);
        _walletViewer = WalletViewer(contracts.walletViewer);
        _faucet = Faucet(contracts.faucet);
        _bridgerL2 = BridgerL2(contracts.bridgerL2);
        _inflator = KintoInflator(contracts.inflator);
        _engenGovernance = EngenGovernance(contracts.engenGovernance);

        // grant kyc provider role to _kycProvider on kintoID
        bytes32 role = _kintoID.KYC_PROVIDER_ROLE();
        vm.prank(_owner);
        _kintoID.grantRole(role, _kycProvider);

        // approve wallet's owner KYC
        approveKYC(_kycProvider, _owner, _ownerPk);

        // deploy latest KintoWallet version through wallet factory
        vm.prank(_owner);
        _kintoWallet = _walletFactory.createAccount(_owner, _recoverer, 0);

        // fund wallet on sponsor paymaster
        fundSponsorForApp(_owner, address(_kintoWallet));

        assertEq(_kintoWallet.owners(0), _owner);
        assertEq(_entryPoint.walletFactory(), address(_walletFactory));
        assertEq(_kintoWallet.getOwnersCount(), 1);

        etchEngenCredits();
    }

    function setUpKintoFork() public {
        string memory rpc = vm.rpcUrl("kinto");
        require(bytes(rpc).length > 0, "KINTO_RPC_URL is not set");

        // create Kinto fork
        vm.createSelectFork(rpc);

        // Deal ETH to _owner
        vm.deal(_owner, 1e20);

        // read mainnet contracts from addresses.json
        _entryPoint = IKintoEntryPoint(_getChainDeployment("EntryPoint"));
        _kintoAppRegistry = KintoAppRegistry(_getChainDeployment("KintoAppRegistry"));
        _kintoID = KintoID(_getChainDeployment("KintoID"));
        _walletFactory = KintoWalletFactory(_getChainDeployment("KintoWalletFactory"));
        _kintoWallet = IKintoWallet(_getChainDeployment("KintoWallet-admin"));
        _engenCredits = EngenCredits(_getChainDeployment("EngenCredits"));
        _engenBadges = EngenBadges(_getChainDeployment("EngenBadges"));
        _paymaster = SponsorPaymaster(_getChainDeployment("SponsorPaymaster"));
        _kycViewer = KYCViewer(_getChainDeployment("KYCViewer"));
        _walletViewer = WalletViewer(_getChainDeployment("WalletViewer"));
        _faucet = Faucet(payable(_getChainDeployment("Faucet")));
        _bridgerL2 = BridgerL2(_getChainDeployment("BridgerL2"));
        _inflator = KintoInflator(_getChainDeployment("KintoInflator"));
        _engenGovernance = EngenGovernance(payable(_getChainDeployment("EngenGovernance")));

        // grant admin role to _owner on kintoID
        bytes32 role = _kintoID.DEFAULT_ADMIN_ROLE();
        vm.prank(vm.envAddress("LEDGER_ADMIN"));
        _kintoID.grantRole(role, _owner);

        // grant KYC provider role to _kycProvider and _owner on kintoID
        role = _kintoID.KYC_PROVIDER_ROLE();
        vm.prank(_owner);
        _kintoID.grantRole(role, _kycProvider);
        vm.prank(_owner);
        _kintoID.grantRole(role, _owner);

        // grant UPGRADER role to _owner on kintoID
        role = _kintoID.UPGRADER_ROLE();
        vm.prank(_owner);
        _kintoID.grantRole(role, _owner);

        // approve wallet's owner KYC
        approveKYC(_kycProvider, _owner, _ownerPk);

        // for geth allowed contracts, transfer ownership from LEDGER to _owner
        vm.startPrank(_kintoAppRegistry.owner());
        _kintoAppRegistry.transferOwnership(_owner);
        _walletFactory.transferOwnership(_owner);
        _paymaster.transferOwnership(_owner);
        vm.stopPrank();

        // for other contracts, transfer ownership from KintoWallet-admin to _owner
        // TODO: we should actually use the KintoWallet-admin and adjust tests so they use the handleOps
        vm.startPrank(address(_kintoWallet));
        _engenCredits.transferOwnership(_owner);
        _kycViewer.transferOwnership(_owner);
        _faucet.transferOwnership(_owner);
        vm.stopPrank();

        // TODO: Remove once the wallet is fixed
        etchWallet(0xe1FcA7f6d88E30914089b600A73eeF72eaC7f601);

        // change _kintoWallet owner to _owner so we use it on tests
        changeWalletOwner(_owner, _kycProvider);
    }

    function etchWallet(address wallet) internal {
        KintoWallet impl = new KintoWallet(
            IEntryPoint(_getChainDeployment("EntryPoint")),
            IKintoID(_getChainDeployment("KintoID")),
            IKintoAppRegistry(_getChainDeployment("KintoAppRegistry"))
        );
        vm.etch(wallet, address(impl).code);
    }

    function etchEngenCredits() internal {
        EngenCredits impl = new EngenCredits();
        vm.etch(0xD1295F0d8789c3E0931A04F91049dB33549E9C8F, address(impl).code);
    }
}
