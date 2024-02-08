// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "@aa/core/EntryPoint.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "../src/KintoID.sol";
import "../src/viewers/KYCViewer.sol";
import "../src/wallet/KintoWallet.sol";
import "../src/wallet/KintoWalletFactory.sol";
import "../src/paymasters/SponsorPaymaster.sol";
import "../src/wallet/KintoWallet.sol";
import "../src/apps/KintoAppRegistry.sol";
import "../src/tokens/EngenCredits.sol";
import "../src/Faucet.sol";

import "../test/helpers/Create2Helper.sol";
import "../test/helpers/ArtifactsReader.sol";
import "../test/helpers/UUPSProxy.sol";

import "forge-std/console.sol";
import "forge-std/Script.sol";

contract DeployerScript is Create2Helper, ArtifactsReader {
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

    // KYC Viewer
    KYCViewer public viewer;
    KYCViewer public viewerImpl;

    // Engen Credits
    EngenCredits public engenCredits;
    EngenCredits public engenCreditsImpl;

    // Faucet
    Faucet public faucet;
    Faucet public faucetImpl;

    // whether to write addresses to a file or not (and console.log them)
    bool write;

    // if set, will broadcast transactions with this private key
    uint256 privateKey;

    function setUp() public {}

    struct DeployedContracts {
        EntryPoint entryPoint;
        SponsorPaymaster paymaster;
        KintoID kintoID;
        KintoWallet wallet;
        KintoWalletFactory factory;
        KintoAppRegistry registry;
        KYCViewer viewer;
        EngenCredits engenCredits;
        Faucet faucet;
    }

    function runAndReturnResults(uint256 _privateKey) public returns (DeployedContracts memory contracts) {
        privateKey = _privateKey;
        _run();
        contracts = DeployedContracts(
            entryPoint, paymaster, kintoID, wallet, factory, kintoRegistry, viewer, engenCredits, faucet
        );
    }

    function run() public {
        write = true;
        _run();
    }

    function _run() internal {
        if (write) console.log("Running on chain ID: ", vm.toString(block.chainid));
        if (write) console.log("Executing with address", msg.sender);
        if (write) console.log("-----------------------------------\n");

        // write addresses to a file
        if (write) vm.writeFile(_getAddressesFile(), "{\n");

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

        // deploy Faucet
        (faucet, faucetImpl) = deployFaucet();

        // deploy KYCViewer
        (viewer, viewerImpl) = deployKYCViewer();

        if (write) vm.writeLine(_getAddressesFile(), "}\n");
    }

    function deployKintoID() public returns (KintoID _kintoID, KintoID _kintoIDImpl) {
        bytes memory creationCode = type(KintoID).creationCode;
        bytes memory bytecode = abi.encodePacked(creationCode, abi.encode(address(0)));
        (address proxy, address implementation) = _deploy("KintoID", creationCode, bytecode);
        _kintoID = KintoID(payable(proxy));
        _kintoIDImpl = KintoID(payable(implementation));

        privateKey > 0 ? vm.broadcast(privateKey) : vm.broadcast();
        _kintoID.initialize();
    }

    function deployEntryPoint() public returns (EntryPoint _entryPoint) {
        bytes memory creationCode = type(EntryPoint).creationCode;
        bytes memory bytecode = abi.encodePacked(creationCode, abi.encode(""));
        (, address implementation) = _deploy("EntryPoint", creationCode, bytecode);
        _entryPoint = EntryPoint(payable(implementation));
    }

    function deployWalletFactory()
        public
        returns (KintoWalletFactory _walletFactory, KintoWalletFactory _walletFactoryImpl)
    {
        // deploy a dummy KintoWallet that will be then replaced by the factory
        privateKey > 0 ? vm.broadcast(privateKey) : vm.broadcast();
        KintoWallet dummy =
            new KintoWallet{salt: 0}(IEntryPoint(address(0)), IKintoID(address(0)), IKintoAppRegistry(address(0)));

        // deploy factory implementation
        bytes memory creationCode = type(KintoWalletFactory).creationCode;
        bytes memory bytecode = abi.encodePacked(creationCode, abi.encode(address(dummy)));
        (address proxy, address implementation) = _deploy("KintoWalletFactory", creationCode, bytecode);
        _walletFactory = KintoWalletFactory(payable(proxy));
        _walletFactoryImpl = KintoWalletFactory(payable(implementation));

        privateKey > 0 ? vm.broadcast(privateKey) : vm.broadcast();
        _walletFactory.initialize(kintoID);

        // set wallet factory in EntryPoint
        if (write) console.log("Setting wallet factory in entry point to: ", address(_walletFactory));
        privateKey > 0 ? vm.broadcast(privateKey) : vm.broadcast();
        entryPoint.setWalletFactory(address(_walletFactory));
    }

    function deployKintoWallet() public returns (KintoWallet _kintoWallet) {
        bytes memory creationCode = type(KintoWallet).creationCode;
        bytes memory bytecode =
            abi.encodePacked(creationCode, abi.encode(address(entryPoint), address(kintoID), address(kintoRegistry)));
        (, address implementation) = _deploy("KintoWallet", creationCode, bytecode);
        _kintoWallet = KintoWallet(payable(implementation));

        // set KintoWallet implementation in WalletFactory
        if (write) console.log("Upgrading wallet factory implementation to: ", address(_kintoWallet));
        privateKey > 0 ? vm.broadcast(privateKey) : vm.broadcast();
        factory.upgradeAllWalletImplementations(KintoWallet(payable(_kintoWallet)));
    }

    function deployPaymaster()
        public
        returns (SponsorPaymaster _sponsorPaymaster, SponsorPaymaster _sponsorPaymasterImpl)
    {
        bytes memory creationCode = type(SponsorPaymaster).creationCode;
        bytes memory bytecode = abi.encodePacked(creationCode, abi.encode(address(entryPoint)));
        (address proxy, address implementation) = _deploy("SponsorPaymaster", creationCode, bytecode);
        _sponsorPaymaster = SponsorPaymaster(payable(proxy));
        _sponsorPaymasterImpl = SponsorPaymaster(payable(implementation));

        address owner = privateKey > 0 ? vm.addr(privateKey) : msg.sender;
        privateKey > 0 ? vm.broadcast(privateKey) : vm.broadcast();
        _sponsorPaymaster.initialize(owner, kintoRegistry, kintoID); // owner is the address that deploys the paymaster
    }

    function deployKintoRegistry()
        public
        returns (KintoAppRegistry _kintoRegistry, KintoAppRegistry _kintoRegistryImpl)
    {
        bytes memory creationCode = type(KintoAppRegistry).creationCode;
        bytes memory bytecode = abi.encodePacked(creationCode, abi.encode(address(factory)));
        (address proxy, address implementation) = _deploy("KintoAppRegistry", creationCode, bytecode);
        _kintoRegistry = KintoAppRegistry(payable(proxy));
        _kintoRegistryImpl = KintoAppRegistry(payable(implementation));

        privateKey > 0 ? vm.broadcast(privateKey) : vm.broadcast();
        _kintoRegistry.initialize();
    }

    function deployKYCViewer() public returns (KYCViewer _kycViewer, KYCViewer _kycViewerImpl) {
        bytes memory creationCode = type(KYCViewer).creationCode;
        bytes memory bytecode =
            abi.encodePacked(creationCode, abi.encode(address(factory)), abi.encode(address(faucet)));
        (address proxy, address implementation) = _deploy("KYCViewer", creationCode, bytecode);
        _kycViewer = KYCViewer(payable(proxy));
        _kycViewerImpl = KYCViewer(payable(implementation));

        privateKey > 0 ? vm.broadcast(privateKey) : vm.broadcast();
        _kycViewer.initialize();
    }

    function deployEngenCredits() public returns (EngenCredits _engenCredits, EngenCredits _engenCreditsImpl) {
        bytes memory creationCode = type(EngenCredits).creationCode;
        bytes memory bytecode = abi.encodePacked(creationCode, abi.encode(address(entryPoint)));
        (address proxy, address implementation) = _deploy("EngenCredits", creationCode, bytecode);
        _engenCredits = EngenCredits(payable(proxy));
        _engenCreditsImpl = EngenCredits(payable(implementation));

        privateKey > 0 ? vm.broadcast(privateKey) : vm.broadcast();
        _engenCredits.initialize();
    }

    function deployFaucet() public returns (Faucet _faucet, Faucet _faucetImpl) {
        bytes memory creationCode = type(Faucet).creationCode;
        bytes memory bytecode = abi.encodePacked(creationCode, abi.encode(address(factory)));
        (address proxy, address implementation) = _deploy("Faucet", creationCode, bytecode);
        _faucet = Faucet(payable(proxy));
        _faucetImpl = Faucet(payable(implementation));

        privateKey > 0 ? vm.broadcast(privateKey) : vm.broadcast();
        _faucet.initialize();
    }

    /// @dev deploys proxy contract from deployer
    function _deploy(string memory contractName, bytes memory creationCode, bytes memory bytecode)
        internal
        returns (address proxy, address implementation)
    {
        bool isEntryPoint = keccak256(abi.encodePacked(contractName)) == keccak256(abi.encodePacked("EntryPoint"));
        bool isWallet = keccak256(abi.encodePacked(contractName)) == keccak256(abi.encodePacked("KintoWallet"));
        proxy = _getChainDeployment(contractName);

        if (!isWallet && proxy != address(0)) revert("Proxy contract already deployed");

        // (1). deploy implementation
        implementation = computeAddress(0, abi.encodePacked(creationCode));
        if (!isContract(implementation)) {
            // deploy implementation
            privateKey > 0 ? vm.broadcast(privateKey) : vm.broadcast();
            implementation = Create2.deploy(0, 0, bytecode);

            require(implementation != address(0), "Failed to deploy implementation");
            if (write) console.log(contractName, "implementation deployed at:", implementation);

            // write address to a file
            if (write) {
                vm.writeLine(
                    _getAddressesFile(),
                    string.concat('"', contractName, '-impl": "', vm.toString(address(implementation)), '",')
                );
            }
        }

        // (2). deploy Proxy contract
        if (!isEntryPoint && !isWallet) {
            proxy = computeAddress(
                0, abi.encodePacked(type(UUPSProxy).creationCode, abi.encode(address(implementation), ""))
            );

            if (!isContract(proxy)) {
                // deploy proxy contract
                privateKey > 0 ? vm.broadcast(privateKey) : vm.broadcast();
                proxy = address(new UUPSProxy{salt: 0}(address(implementation), ""));
            }

            if (write) console.log(contractName, "proxy deployed at:", proxy);

            // write address to a file
            if (write) {
                vm.writeLine(
                    _getAddressesFile(), string.concat('"', contractName, '": "', vm.toString(address(proxy)), '",')
                );
            }
        }
    }
}
