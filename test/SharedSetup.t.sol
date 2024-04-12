// SPDX-License-Identifier: MIT
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

// scripts & migrations
import "../script/deploy.s.sol";
import {KintoMigration29DeployScript} from "../script/migrations/29-multiple_upgrade_3.sol";

contract SharedSetup is UserOp, AATestScaffolding, ArtifactsReader {
    bool fork = false;

    Counter counter;
    uint256[] privateKeys;
    uint256 mainnetFork;

    // events
    event UserOperationRevertReason(
        bytes32 indexed userOpHash, address indexed sender, uint256 nonce, bytes revertReason
    );
    event KintoWalletInitialized(IEntryPoint indexed entryPoint, address indexed owner);
    event WalletPolicyChanged(uint256 newPolicy, uint256 oldPolicy);
    event RecovererChanged(address indexed newRecoverer, address indexed recoverer);
    event PostOpRevertReason(bytes32 indexed userOpHash, address indexed sender, uint256 nonce, bytes revertReason);
    event AppKeyCreated(address indexed appKey, address indexed signer);

    function setUp() public virtual {
        try vm.envBool("FORK") returns (bool _fork) {
            fork = _fork;
        } catch {}

        // give some eth to _owner
        vm.deal(_owner, 1e20);

        // deploy contracts using deploy script
        DeployerScript deployer = new DeployerScript();

        if (fork) {
            string memory rpc = vm.envString("KINTO_RPC_URL");
            require(bytes(rpc).length > 0, "KINTO_RPC_URL is not set");

            // create fork from mainnet with chain ID 7887
            vm.chainId(7887);
            mainnetFork = vm.createFork(rpc);
            vm.selectFork(mainnetFork);
            assertEq(vm.activeFork(), mainnetFork);
            console.log("Running tests on fork from mainnet at:", rpc);

            // read mainnet contracts from addresses.json
            _entryPoint = IKintoEntryPoint(_getChainDeployment("EntryPoint"));
            _kintoAppRegistry = KintoAppRegistry(_getChainDeployment("KintoAppRegistry"));
            _kintoID = KintoID(_getChainDeployment("KintoID"));
            _walletFactory = KintoWalletFactory(_getChainDeployment("KintoWalletFactory"));
            _kintoWallet = IKintoWallet(_getChainDeployment("KintoWallet-admin"));
            _engenCredits = EngenCredits(_getChainDeployment("EngenCredits"));
            _paymaster = SponsorPaymaster(_getChainDeployment("SponsorPaymaster"));
            _kycViewer = KYCViewer(_getChainDeployment("KYCViewer"));
            _faucet = Faucet(payable(_getChainDeployment("Faucet")));
            _bridgerL2 = BridgerL2(_getChainDeployment("BridgerL2"));
            _inflator = KintoInflator(_getChainDeployment("KintoInflator"));

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

            // change _kintoWallet owner to _owner so we use it on tesets
            changeWalletOwner(_owner, _kycProvider);
        } else {
            console.log("Running tests locally");
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
            _bridgerL2 = BridgerL2(contracts.bridgerL2);
            _inflator = KintoInflator(contracts.inflator);

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

            // run all migrations
            // TODO: for future improvements, we could run all migrations here
            // @dev every time we create a new migration, we need to add it here
            // vm.setEnv("PRIVATE_KEY", vm.toString(_ownerPk));
            // vm.setEnv("TEST_MODE", "true");
            // vm.setEnv("KINTO_ADMIN_WALLET", vm.toString(address(_kintoWallet)));
            // (new KintoMigration29DeployScript()).run();
        }

        // label addresses
        vm.label(address(_entryPoint), "EntryPoint");
        vm.label(address(_kintoAppRegistry), "KintoAppRegistry");
        vm.label(address(_kintoID), "KintoID");
        vm.label(address(_walletFactory), "KintoWalletFactory");
        vm.label(address(_kintoWallet), "KintoWallet");
        vm.label(address(_engenCredits), "EngenCredits");
        vm.label(address(_paymaster), "SponsorPaymaster");
        vm.label(address(_kycViewer), "KYCViewer");
        vm.label(address(_faucet), "Faucet");
        vm.label(address(_bridgerL2), "BridgerL2");

        // all tests will use 1 private key (_ownerPk) unless otherwise specified
        privateKeys = new uint256[](1);
        privateKeys[0] = _ownerPk;

        // deploy Counter contract
        counter = new Counter();
        assertEq(counter.count(), 0);

        // give some eth to _owner
        vm.deal(_owner, 1e20);

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
