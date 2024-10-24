// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@aa/core/EntryPoint.sol";

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import {BaseTest} from "@kinto-core-test/helpers/BaseTest.sol";

import "@kinto-core/KintoID.sol";
import "@kinto-core/bridger/BridgerL2.sol";
import "@kinto-core/viewers/KYCViewer.sol";
import "@kinto-core/viewers/WalletViewer.sol";
import "@kinto-core/wallet/KintoWallet.sol";
import "@kinto-core/wallet/KintoWalletFactory.sol";
import {RewardsDistributor} from "@kinto-core/liquidity-mining/RewardsDistributor.sol";
import "@kinto-core/paymasters/SponsorPaymaster.sol";
import "@kinto-core/wallet/KintoWallet.sol";
import "@kinto-core/apps/KintoAppRegistry.sol";
import "@kinto-core/tokens/EngenCredits.sol";
import "@kinto-core/tokens/EngenBadges.sol";
import "@kinto-core/Faucet.sol";
import "@kinto-core/inflators/KintoInflator.sol";
import "@kinto-core/inflators/BundleBulker.sol";
import "@kinto-core/governance/EngenGovernance.sol";
import "@kinto-core-test/helpers/Create2Helper.sol";
import "@kinto-core-test/helpers/ArtifactsReader.sol";
import "@kinto-core-test/helpers/UUPSProxy.sol";
import {BridgedKinto} from "@kinto-core/tokens/bridged/BridgedKinto.sol";

import {DeployerHelper} from "@kinto-core-script/utils/DeployerHelper.sol";

import "forge-std/console2.sol";
import "forge-std/Script.sol";

contract DeployerScript is Create2Helper, DeployerHelper {
    // EntryPoint
    EntryPoint public entryPoint;

    // Sponsor Paymaster
    SponsorPaymaster public paymasterImpl;
    SponsorPaymaster public paymaster;

    // Kinto ID
    KintoID public kintoIDImpl;
    KintoID public kintoID;

    // Wallet & Factory
    KintoWallet public wallet;
    KintoWalletFactory public factoryImpl;
    KintoWalletFactory public factory;

    // Kinto Registry
    KintoAppRegistry public kintoRegistry;
    KintoAppRegistry public registryImpl;

    // BridgedKinto
    BridgedKinto public bridgedKinto;
    BridgedKinto public bridgedKintoImpl;

    // RewardsDistributor
    RewardsDistributor public rewardsDistributor;
    RewardsDistributor public rewardsDistributorImpl;

    // KYC Viewer
    KYCViewer public viewer;
    KYCViewer public viewerImpl;

    // Wallet Viewer
    WalletViewer public walletViewer;
    WalletViewer public walletViewerImpl;

    // Engen Credits
    EngenCredits public engenCredits;
    EngenCredits public engenCreditsImpl;

    // Engen Badges
    EngenBadges public engenBadges;
    EngenBadges public engenBadgesImpl;

    // Bridger
    BridgerL2 public bridgerL2;
    BridgerL2 public bridgerL2Impl;

    // Faucet
    Faucet public faucet;
    Faucet public faucetImpl;

    // Inflator
    KintoInflator public inflator;
    KintoInflator public inflatorImpl;

    // BundleBulker
    BundleBulker public bundleBulker;
    BundleBulker public bundleBulkerImpl;

    // Engen Governance
    EngenGovernance public engenGovernance;

    // whether to write addresses to a file or not (and console.log them)
    bool write;

    // whether to log or not
    bool log;

    // if set, will broadcast transactions with this private key
    uint256 privateKey;
    address owner;

    function setUp() public {}

    struct DeployedContracts {
        EntryPoint entryPoint;
        SponsorPaymaster paymaster;
        KintoID kintoID;
        KintoWallet wallet;
        KintoWalletFactory factory;
        KintoAppRegistry registry;
        KYCViewer viewer;
        WalletViewer walletViewer;
        EngenCredits engenCredits;
        EngenBadges engenBadges;
        Faucet faucet;
        BridgerL2 bridgerL2;
        KintoInflator inflator;
        EngenGovernance engenGovernance;
        RewardsDistributor rewardsDistributor;
        BridgedKinto bridgedKinto;
    }

    // @dev this is used for tests
    function runAndReturnResults(uint256 _privateKey) public returns (DeployedContracts memory contracts) {
        privateKey = _privateKey;
        owner = privateKey > 0 ? vm.addr(privateKey) : msg.sender;
        write = false;
        log = false;

        // remove addresses.json file if it exists
        try vm.removeFile(_getAddressesFile(block.chainid)) {} catch {}

        _run();
        contracts = DeployedContracts(
            entryPoint,
            paymaster,
            kintoID,
            wallet,
            factory,
            kintoRegistry,
            viewer,
            walletViewer,
            engenCredits,
            engenBadges,
            faucet,
            bridgerL2,
            inflator,
            engenGovernance,
            rewardsDistributor,
            bridgedKinto
        );
    }

    function run() public {
        write = true;
        log = true;
        _run();
    }

    function _run() internal {
        if (log) console.log("Running on chain ID: ", vm.toString(block.chainid));
        if (log) console.log("Executing with address", msg.sender);
        if (log) console.log("-----------------------------------\n");

        // write addresses to a file
        if (write) {
            // create dir if it doesn't exist
            string memory dir = _getAddressesDir();
            if (!vm.isDir(dir)) vm.createDir(dir, true);
            vm.writeFile(_getAddressesFile(), "{\n");
        }

        // deploy KintoID
        (kintoID, kintoIDImpl) = deployKintoID();

        // deploy EntryPoint
        entryPoint = deployEntryPoint();

        // deploy KintoWalletFactory
        (factory, factoryImpl) = deployWalletFactory();

        // deploy KintoRegistry
        (kintoRegistry, registryImpl) = deployKintoRegistry();

        // deploy KintoWallet
        wallet = deployKintoWallet();

        // deploy SponsorPaymaster
        (paymaster, paymasterImpl) = deployPaymaster();

        // deploy EngenCredits
        (engenCredits, engenCreditsImpl) = deployEngenCredits();

        // deploy EngenBadges
        (engenBadges, engenBadgesImpl) = deployEngenBadges();

        // deploy bridger l2
        (bridgerL2, bridgerL2Impl) = deployBridgerL2();

        // deploy Faucet
        (faucet, faucetImpl) = deployFaucet();

        // deploy BundleBulker & Inflator
        (inflator, inflatorImpl) = deployInflator();
        (bundleBulker, bundleBulkerImpl) = deployBundleBulker();

        // deploy KYCViewer
        (viewer, viewerImpl) = deployKYCViewer();

        // deploy WalletViewer
        (walletViewer, walletViewerImpl) = deployWalletViewer();

        // deploy governance
        (engenGovernance) = deployGovernance();

        // deploy bridgedKinto
        (bridgedKinto, bridgedKintoImpl) = deployBridgedKinto();

        // deploy rewardsDistributor
        (rewardsDistributor, rewardsDistributorImpl) = deployRewardsDistributor();

        privateKey > 0 ? vm.broadcast(privateKey) : vm.broadcast();
        bridgedKinto.setMiningContract(address(rewardsDistributor));

        // deploy & upgrade KintoID implementation (passing the factory)
        bytes memory bytecode =
            abi.encodePacked(type(KintoID).creationCode, abi.encode(address(factory), address(faucet)));
        kintoIDImpl = KintoID(_deployImplementation("KintoID", bytecode, true));
        privateKey > 0 ? vm.broadcast(privateKey) : vm.broadcast();
        kintoID.upgradeTo(address(kintoIDImpl));

        // upgrade factory
        bytecode = abi.encodePacked(
            type(KintoWalletFactory).creationCode, abi.encode(wallet, kintoRegistry, kintoID, rewardsDistributor)
        );
        privateKey > 0 ? vm.broadcast(privateKey) : vm.broadcast();
        address implementation = Create2.deploy(0, 0, bytecode);
        privateKey > 0 ? vm.broadcast(privateKey) : vm.broadcast();
        factory.upgradeTo(implementation);

        // upgrade app registry
        bytecode = abi.encodePacked(type(KintoAppRegistry).creationCode, abi.encode(factory, paymaster));
        privateKey > 0 ? vm.broadcast(privateKey) : vm.broadcast();
        implementation = Create2.deploy(0, 0, bytecode);
        privateKey > 0 ? vm.broadcast(privateKey) : vm.broadcast();
        kintoRegistry.upgradeTo(implementation);

        if (write) vm.writeLine(_getAddressesFile(), "}\n");

        setSystemContracts();
    }

    function deployKintoID() public returns (KintoID _kintoID, KintoID _kintoIDImpl) {
        // deploy a dummy KintoID that will be then replaced after the factory has been deployed by the script
        privateKey > 0 ? vm.broadcast(privateKey) : vm.broadcast();
        KintoID dummy = new KintoID{salt: 0}(address(0), address(0));

        address proxy = _deployProxy("KintoID", address(dummy), false);
        _kintoID = KintoID(payable(proxy));
        _kintoIDImpl = KintoID(dummy);

        privateKey > 0 ? vm.broadcast(privateKey) : vm.broadcast();
        _kintoID.initialize();
    }

    function deployEntryPoint() public returns (EntryPoint _entryPoint) {
        bytes memory creationCode = type(EntryPoint).creationCode;
        bytes memory bytecode = abi.encodePacked(creationCode, abi.encode(""));
        address implementation = _deployImplementation("EntryPoint", bytecode, false);
        _entryPoint = EntryPoint(payable(implementation));
    }

    function deployWalletFactory()
        public
        returns (KintoWalletFactory _walletFactory, KintoWalletFactory _walletFactoryImpl)
    {
        // deploy a dummy KintoWallet that will be then replaced by the factory
        privateKey > 0 ? vm.broadcast(privateKey) : vm.broadcast();
        KintoWallet dummy = new KintoWallet{salt: 0}(
            IEntryPoint(address(0)),
            IKintoID(address(0)),
            IKintoAppRegistry(address(0)),
            IKintoWalletFactory(address(0))
        );

        // deploy factory implementation
        bytes memory creationCode = type(KintoWalletFactory).creationCode;
        bytes memory bytecode = abi.encodePacked(creationCode, abi.encode(dummy, dummy, kintoID, dummy));
        address implementation = _deployImplementation("KintoWalletFactory", bytecode, false);
        address proxy = _deployProxy("KintoWalletFactory", implementation, false);

        _walletFactory = KintoWalletFactory(payable(proxy));
        _walletFactoryImpl = KintoWalletFactory(payable(implementation));

        privateKey > 0 ? vm.broadcast(privateKey) : vm.broadcast();
        _walletFactory.initialize();

        // set wallet factory in EntryPoint
        if (log) console.log("Setting wallet factory in entry point to: ", address(_walletFactory));
        privateKey > 0 ? vm.broadcast(privateKey) : vm.broadcast();
        entryPoint.setWalletFactory(address(_walletFactory));
    }

    function deployKintoWallet() public returns (KintoWallet _kintoWallet) {
        bytes memory creationCode = type(KintoWallet).creationCode;
        bytes memory bytecode = abi.encodePacked(
            creationCode, abi.encode(address(entryPoint), address(kintoID), address(kintoRegistry), address(factory))
        );
        address implementation = _deployImplementation("KintoWallet", bytecode, false);
        _kintoWallet = KintoWallet(payable(implementation));

        // set KintoWallet implementation in WalletFactory
        if (log) console.log("Upgrading wallet factory implementation to: ", address(_kintoWallet));
        privateKey > 0 ? vm.broadcast(privateKey) : vm.broadcast();
        factory.upgradeAllWalletImplementations(KintoWallet(payable(_kintoWallet)));
    }

    function deployPaymaster()
        public
        returns (SponsorPaymaster _sponsorPaymaster, SponsorPaymaster _sponsorPaymasterImpl)
    {
        bytes memory creationCode = type(SponsorPaymaster).creationCode;
        bytes memory bytecode = abi.encodePacked(creationCode, abi.encode(address(entryPoint), address(factory)));
        address implementation = _deployImplementation("SponsorPaymaster", bytecode, false);
        address proxy = _deployProxy("SponsorPaymaster", implementation, false);

        _sponsorPaymaster = SponsorPaymaster(payable(proxy));
        _sponsorPaymasterImpl = SponsorPaymaster(payable(implementation));

        privateKey > 0 ? vm.broadcast(privateKey) : vm.broadcast();
        _sponsorPaymaster.initialize(owner, kintoRegistry, kintoID); // owner is the address that deploys the paymaster
    }

    function deployKintoRegistry()
        public
        returns (KintoAppRegistry _kintoRegistry, KintoAppRegistry _kintoRegistryImpl)
    {
        bytes memory creationCode = type(KintoAppRegistry).creationCode;
        bytes memory bytecode = abi.encodePacked(creationCode, abi.encode(address(factory), address(paymaster)));
        address implementation = _deployImplementation("KintoAppRegistry", bytecode, false);
        address proxy = _deployProxy("KintoAppRegistry", implementation, false);

        _kintoRegistry = KintoAppRegistry(payable(proxy));
        _kintoRegistryImpl = KintoAppRegistry(payable(implementation));
        privateKey > 0 ? vm.broadcast(privateKey) : vm.broadcast();
        _kintoRegistry.initialize();
    }

    function deployKYCViewer() public returns (KYCViewer _kycViewer, KYCViewer _kycViewerImpl) {
        bytes memory creationCode = type(KYCViewer).creationCode;
        bytes memory bytecode = abi.encodePacked(
            creationCode,
            abi.encode(address(factory)),
            abi.encode(address(faucet)),
            abi.encode(address(engenCredits)),
            abi.encode(address(kintoRegistry))
        );
        address implementation = _deployImplementation("KYCViewer", bytecode, false);
        address proxy = _deployProxy("KYCViewer", implementation, false);

        _kycViewer = KYCViewer(payable(proxy));
        _kycViewerImpl = KYCViewer(payable(implementation));
        privateKey > 0 ? vm.broadcast(privateKey) : vm.broadcast();
        _kycViewer.initialize();
    }

    function deployWalletViewer() public returns (WalletViewer _walletViewer, WalletViewer _walletViewerImpl) {
        bytes memory creationCode = type(WalletViewer).creationCode;
        bytes memory bytecode =
            abi.encodePacked(creationCode, abi.encode(address(factory)), abi.encode(address(kintoRegistry)));
        address implementation = _deployImplementation("WalletViewer", bytecode, false);
        address proxy = _deployProxy("WalletViewer", implementation, false);

        _walletViewer = WalletViewer(payable(proxy));
        _walletViewerImpl = WalletViewer(payable(implementation));

        privateKey > 0 ? vm.broadcast(privateKey) : vm.broadcast();
        _walletViewer.initialize();
    }

    function deployEngenCredits() public returns (EngenCredits _engenCredits, EngenCredits _engenCreditsImpl) {
        bytes memory creationCode = type(EngenCredits).creationCode;
        bytes memory bytecode = abi.encodePacked(creationCode, abi.encode(address(entryPoint)));
        address implementation = _deployImplementation("EngenCredits", bytecode, false);
        address proxy = _deployProxy("EngenCredits", implementation, false);

        _engenCredits = EngenCredits(payable(proxy));
        _engenCreditsImpl = EngenCredits(payable(implementation));

        privateKey > 0 ? vm.broadcast(privateKey) : vm.broadcast();
        _engenCredits.initialize();
    }

    function deployEngenBadges() public returns (EngenBadges _engenBadges, EngenBadges _engenBadgesImpl) {
        bytes memory creationCode = type(EngenBadges).creationCode;
        bytes memory bytecode = abi.encodePacked(creationCode, abi.encode(address(entryPoint)));
        address implementation = _deployImplementation("EngenBadges", bytecode, false);
        address proxy = _deployProxy("EngenBadges", implementation, false);

        _engenBadges = EngenBadges(payable(proxy));
        _engenBadgesImpl = EngenBadges(payable(implementation));

        //privateKey > 0 ? vm.broadcast(privateKey) : vm.broadcast();
        //_engenBadges.initialize("https://api.example.com/metadata/");
    }

    function deployBridgerL2() public returns (BridgerL2 _bridgerL2, BridgerL2 _bridgerL2Impl) {
        bytes memory creationCode = type(BridgerL2).creationCode;
        bytes memory bytecode = abi.encodePacked(creationCode, abi.encode(address(factory)));
        address implementation = _deployImplementation("BridgerL2", bytecode, false);
        address proxy = _deployProxy("BridgerL2", implementation, false);

        _bridgerL2 = BridgerL2(payable(proxy));
        _bridgerL2Impl = BridgerL2(payable(implementation));

        privateKey > 0 ? vm.broadcast(privateKey) : vm.broadcast();
        _bridgerL2.initialize();
    }

    function deployFaucet() public returns (Faucet _faucet, Faucet _faucetImpl) {
        bytes memory creationCode = type(Faucet).creationCode;
        bytes memory bytecode = abi.encodePacked(creationCode, abi.encode(address(factory)));
        address implementation = _deployImplementation("Faucet", bytecode, false);
        address proxy = _deployProxy("Faucet", implementation, false);

        _faucet = Faucet(payable(proxy));
        _faucetImpl = Faucet(payable(implementation));

        privateKey > 0 ? vm.broadcast(privateKey) : vm.broadcast();
        _faucet.initialize();
    }

    function deployInflator() public returns (KintoInflator _inflator, KintoInflator _inflatorImpl) {
        bytes memory creationCode = type(KintoInflator).creationCode;
        bytes memory bytecode = abi.encodePacked(creationCode, abi.encode(address(entryPoint)));
        address implementation = _deployImplementation("KintoInflator", bytecode, false);
        address proxy = _deployProxy("KintoInflator", implementation, false);

        _inflator = KintoInflator(payable(proxy));
        _inflatorImpl = KintoInflator(payable(implementation));

        privateKey > 0 ? vm.broadcast(privateKey) : vm.broadcast();
        _inflator.initialize();
    }

    function deployBundleBulker() public returns (BundleBulker _bundleBulker, BundleBulker _bundleBulkerImpl) {
        bytes memory creationCode = type(BundleBulker).creationCode;
        bytes memory bytecode = abi.encodePacked(creationCode, abi.encode(address(entryPoint)));
        address implementation = _deployImplementation("BundleBulker", bytecode, false);
        address proxy = _deployProxy("BundleBulker", implementation, false);

        _bundleBulker = BundleBulker(payable(proxy));
        _bundleBulkerImpl = BundleBulker(payable(implementation));
    }

    function deployGovernance() public returns (EngenGovernance _governance) {
        // deploy governance
        bytes memory creationCode = type(EngenGovernance).creationCode;
        bytes memory bytecode = abi.encodePacked(creationCode, abi.encode(address(engenCredits)));
        address implementation = _deployImplementation("EngenGovernance", bytecode, false);
        _governance = EngenGovernance(payable(implementation));
    }

    function deployBridgedKinto() public returns (BridgedKinto proxy, BridgedKinto impl) {
        bytes memory creationCode = type(BridgedKinto).creationCode;
        impl = BridgedKinto(_deployImplementation("BridgedKinto", abi.encodePacked(creationCode), false));
        proxy = BridgedKinto(_deployProxy("BridgedKinto", address(impl), false));
        privateKey > 0 ? vm.broadcast(privateKey) : vm.broadcast();
        proxy.initialize("Kinto Token", "K", owner, owner, owner);
    }

    function deployRewardsDistributor() public returns (RewardsDistributor proxy, RewardsDistributor impl) {
        bytes memory creationCode = type(RewardsDistributor).creationCode;
        bytes memory bytecode = abi.encodePacked(creationCode, abi.encode(bridgedKinto, 1_682_899_200, factory));
        impl = RewardsDistributor(_deployImplementation("RewardsDistributor", bytecode, false));
        proxy = RewardsDistributor(_deployProxy("RewardsDistributor", address(impl), false));
        privateKey > 0 ? vm.broadcast(privateKey) : vm.broadcast();
        proxy.initialize(bytes32(""), 0);
    }

    function setSystemContracts() public {
        address[] memory systemContracts = new address[](4);
        systemContracts[0] = address(kintoID);
        systemContracts[1] = address(factory);
        systemContracts[2] = address(bundleBulker);
        systemContracts[3] = address(entryPoint);
        privateKey > 0 ? vm.broadcast(privateKey) : vm.broadcast();
        kintoRegistry.updateSystemContracts(systemContracts);
    }

    /// @dev deploys both proxy and implementation contracts from deployer
    function _deploy(string memory contractName, bytes memory bytecode)
        internal
        returns (address proxy, address implementation)
    {
        implementation = _deployImplementation(contractName, bytecode, false);
        proxy = _deployProxy(contractName, implementation, false);
    }

    function _deployProxy(string memory contractName, address implementation, bool last)
        internal
        returns (address proxy)
    {
        bool isEntryPoint = keccak256(abi.encodePacked(contractName)) == keccak256(abi.encodePacked("EntryPoint"));
        bool isWallet = keccak256(abi.encodePacked(contractName)) == keccak256(abi.encodePacked("KintoWallet"));
        proxy = _getChainDeployment(contractName);

        if (!isWallet && proxy != address(0)) revert("Proxy contract already deployed");

        // deploy Proxy contract
        if (!isEntryPoint && !isWallet) {
            proxy = computeAddress(
                0, abi.encodePacked(type(UUPSProxy).creationCode, abi.encode(address(implementation), ""))
            );

            if (!isContract(proxy)) {
                // deploy proxy contract
                privateKey > 0 ? vm.broadcast(privateKey) : vm.broadcast();
                proxy = address(new UUPSProxy{salt: 0}(address(implementation), ""));
            }

            if (log) console.log(contractName, "proxy deployed at:", proxy);

            // write address to a file
            if (write) {
                vm.writeLine(
                    _getAddressesFile(),
                    string.concat('"', contractName, '": "', vm.toString(address(proxy)), last ? '"' : '",')
                );
            }
        }
    }

    function _deployImplementation(string memory contractName, bytes memory bytecode, bool last)
        internal
        returns (address implementation)
    {
        bool isEntryPoint = keccak256(abi.encodePacked(contractName)) == keccak256(abi.encodePacked("EntryPoint"));

        // deploy implementation
        privateKey > 0 ? vm.broadcast(privateKey) : vm.broadcast();
        implementation = Create2.deploy(0, 0, bytecode);

        if (log) console.log(contractName, "implementation deployed at:", implementation, false);

        // write address to a file
        if (write) {
            vm.writeLine(
                _getAddressesFile(),
                string.concat(
                    '"',
                    contractName,
                    isEntryPoint ? '": "' : '-impl": "',
                    vm.toString(address(implementation)),
                    last ? '"' : '",'
                )
            );
        }
    }
}
