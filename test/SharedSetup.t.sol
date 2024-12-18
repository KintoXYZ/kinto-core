// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@aa/interfaces/IEntryPoint.sol";

import "@kinto-core/interfaces/IKintoWallet.sol";

import "@kinto-core/wallet/KintoWallet.sol";
import "@kinto-core/sample/Counter.sol";

import "@kinto-core-test/harness/KintoIdHarness.sol";
import "@kinto-core-test/harness/KintoWalletHarness.sol";
import "@kinto-core-test/harness/SponsorPaymasterHarness.sol";
import "@kinto-core-test/harness/KintoAppRegistryHarness.sol";
import "@kinto-core-test/helpers/UserOp.sol";
import "@kinto-core-test/helpers/AATestScaffolding.sol";
import "@kinto-core-test/helpers/ArtifactsReader.sol";
import {RewardsDistributor} from "@kinto-core/liquidity-mining/RewardsDistributor.sol";
import {ForkTest} from "@kinto-core-test/helpers/ForkTest.sol";

// scripts & migrations
import "@kinto-core-script/actions/deploy.s.sol";

import "forge-std/console2.sol";

abstract contract SharedSetup is ForkTest, UserOp, AATestScaffolding, ArtifactsReader {
    Counter internal counter;
    uint256[] internal privateKeys;

    address internal constant KINTO_TOKEN = 0x010700808D59d2bb92257fCafACfe8e5bFF7aB87;
    address internal constant TREASURY = 0x793500709506652Fcc61F0d2D0fDa605638D4293;

    address[] internal users;

    address internal admin;
    address internal alice;
    address internal bob;
    address internal ian;
    address internal hannah;
    address internal george;
    address internal frank;
    address internal david;
    address internal charlie;
    address internal eve;

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
        vm.label(address(_bridgedKinto), "BridgedKinto");
        vm.label(address(_rewardsDistributor), "RewardsDistributor");
    }

    function deployCounter() public {
        // deploy Counter contract
        counter = new Counter();
        assertEq(counter.count(), 0);

        registerApp(address(_kintoWallet), "counter-app", address(counter), new address[](0));
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
        _bridgedKinto = BridgedKinto(contracts.bridgedKinto);
        _rewardsDistributor = RewardsDistributor(contracts.rewardsDistributor);

        // upgrade KintoId to avoid stale KYC on wrap
        vm.startPrank(_owner);
        _kintoID.upgradeTo(address(new KintoIdHarness(address(_walletFactory), address(_faucet))));
        vm.stopPrank();

        // grant kyc provider role to _kycProvider on kintoID
        bytes32 role = _kintoID.KYC_PROVIDER_ROLE();
        vm.prank(_owner);
        _kintoID.grantRole(role, _kycProvider);

        vm.prank(_owner);
        _faucet.startFaucet{value: 1 ether}();

        // approve wallet's owner KYC
        approveKYC(_kycProvider, _owner, _ownerPk);

        // give K tokens to RD
        vm.startPrank(_owner);
        _bridgedKinto.mint(address(_rewardsDistributor), _rewardsDistributor.totalTokens());
        vm.stopPrank();

        // deploy latest KintoWallet version through wallet factory
        vm.prank(_owner);
        _kintoWallet = _walletFactory.createAccount(_owner, _recoverer, 0);

        users = new address[](signers.length);
        for (uint256 i = 0; i < signers.length; i++) {
            approveKYC(_kycProvider, signers[i], signersPk[i]);
            _kintoID.isKYC(signers[i]);
            vm.prank(signers[i]);
            users[i] = address(_walletFactory.createAccount(signers[i], _recoverer, 0));
        }
        // Garbage Solidity can't destruct a dynamic array
        admin = users[0];
        alice = users[1];
        bob = users[2];
        ian = users[3];
        hannah = users[4];
        george = users[5];
        frank = users[6];
        david = users[7];
        charlie = users[8];
        eve = users[9];

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

        address adminWallet = _getChainDeployment("KintoWallet-admin");

        // grant admin role to _owner on kintoID
        bytes32 role = _kintoID.DEFAULT_ADMIN_ROLE();
        vm.prank(adminWallet);
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

        vm.prank(_kintoAppRegistry.owner());
        _kintoAppRegistry.transferOwnership(_owner);

        vm.prank(_walletFactory.owner());
        _walletFactory.transferOwnership(_owner);

        vm.prank(_paymaster.owner());
        _paymaster.transferOwnership(_owner);

        // TODO: we should actually use the KintoWallet-admin and adjust tests so they use the handleOps
        vm.prank(_engenCredits.owner());
        _engenCredits.transferOwnership(_owner);

        vm.prank(_kycViewer.owner());
        _kycViewer.transferOwnership(_owner);

        vm.prank(_faucet.owner());
        _faucet.transferOwnership(_owner);

        // Send K tokens for recovery
        deal(KINTO_TOKEN, address(_kintoWallet), 5e18);

        // change _kintoWallet owner to _owner so we use it on tests
        changeWalletOwner(_owner, _kycProvider);
    }

    function etchWallet(address wallet) internal {
        KintoWallet impl = new KintoWallet(
            IEntryPoint(_getChainDeployment("EntryPoint")),
            IKintoID(_getChainDeployment("KintoID")),
            IKintoAppRegistry(_getChainDeployment("KintoAppRegistry")),
            IKintoWalletFactory(_getChainDeployment("KintoWalletFactory"))
        );
        vm.etch(wallet, address(impl).code);
    }

    function etchEngenCredits() internal {
        EngenCredits impl = new EngenCredits();
        vm.etch(0xD1295F0d8789c3E0931A04F91049dB33549E9C8F, address(impl).code);
    }
}
