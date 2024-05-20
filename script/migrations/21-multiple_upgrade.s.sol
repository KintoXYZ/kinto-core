// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../../src/wallet/KintoWalletFactory.sol";
import "../../src/wallet/KintoWallet.sol";
import "../../src/apps/KintoAppRegistry.sol";
import "../../src/paymasters/SponsorPaymaster.sol";
import "../../src/viewers/KYCViewer.sol";
import "../../src/KintoID.sol";

import "../../test/helpers/Create2Helper.sol";
import "../../test/helpers/ArtifactsReader.sol";
import "../../test/helpers/UUPSProxy.sol";
import "../../test/helpers/UserOp.sol";
import "@kinto-core-script/utils/MigrationHelper.sol";

import "forge-std/Script.sol";
import "forge-std/console.sol";

contract KYCViewerV2 is KYCViewer {
    constructor(address _kintoWalletFactory, address _faucet, address _engenCredits)
        KYCViewer(_kintoWalletFactory, address(0), address(0))
    {}
}

contract KintoWalletFactoryV7 is KintoWalletFactory {
    constructor(IKintoWallet _implAddressP) KintoWalletFactory(_implAddressP) {}
}

contract SponsorPaymasterV4 is SponsorPaymaster {
    constructor(IEntryPoint __entryPoint) SponsorPaymaster(__entryPoint) {}
}

contract KintoWalletV4 is KintoWallet {
    constructor(IEntryPoint _entryPoint, IKintoID _kintoID, IKintoAppRegistry _appRegistry)
        KintoWallet(_entryPoint, _kintoID, _appRegistry)
    {}
}

contract KintoAppRegistryV3 is KintoAppRegistry {
    constructor(IKintoWalletFactory _walletFactory) KintoAppRegistry(_walletFactory) {}
}

contract KintoMigration21DeployScript is Create2Helper, ArtifactsReader, UserOp {
    using ECDSAUpgradeable for bytes32;

    KintoWalletFactory _walletFactory;
    uint256 deployerPrivateKey;

    // NOTE: this migration must be run from the ledger admin
    function run() public {
        console.log("RUNNING ON CHAIN WITH ID", vm.toString(block.chainid));

        deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // execute this script with the with the ledger
        console.log("Executing from address", msg.sender);

        // set wallet factory
        _walletFactory = KintoWalletFactory(payable(_getChainDeployment("KintoWalletFactory")));

        // deploy contracts
        address _paymasterImpl = upgradePaymaster();
        address _registryImpl = upgradeRegistry();
        address _walletImpl = upgradeWallet();
        address _factoryImpl = upgradeFactory();
        (address _kycViewerImpl, address _kycViewerProxy) = upgradeKYCViewer();

        // writes the addresses to a file
        console.log("TODO: Manually add these new addresses to the artifacts file");
        console.log(string.concat("SponsorPaymasterV4-impl: ", vm.toString(address(_paymasterImpl))));
        console.log(string.concat("KintoAppRegistryV3-impl: ", vm.toString(address(_registryImpl))));
        console.log(string.concat("KintoWalletV4-impl: ", vm.toString(address(_walletImpl))));
        console.log(string.concat("KintoWalletFactoryV7-impl: ", vm.toString(address(_factoryImpl))));
        console.log(string.concat("KYCViewerV2-impl: ", vm.toString(address(_kycViewerImpl))));
        console.log(string.concat("KYCViewerV2: ", vm.toString(address(_kycViewerProxy))));
    }

    function upgradePaymaster() public returns (address _paymasterImpl) {
        // (1). deploy new paymaster implementation via wallet factory
        address paymasterProxy = _getChainDeployment("SponsorPaymaster");
        require(paymasterProxy != address(0), "Need to execute main deploy script first");

        bytes memory bytecode =
            abi.encodePacked(type(SponsorPaymasterV4).creationCode, abi.encode(_getChainDeployment("EntryPoint")));

        vm.broadcast(deployerPrivateKey);
        _paymasterImpl = _walletFactory.deployContract(vm.envAddress("LEDGER_ADMIN"), 0, bytecode, bytes32(0));

        // (3). upgrade paymaster to new implementation
        vm.broadcast(); // requires LEDGER_ADMIN
        // vm.prank(vm.envAddress("LEDGER_ADMIN"));
        SponsorPaymaster(payable(paymasterProxy)).upgradeTo(address(_paymasterImpl));
    }

    function upgradeRegistry() public returns (address _registryImpl) {
        // (1). deploy new kinto registry implementation via wallet factory
        address registryProxy = _getChainDeployment("KintoAppRegistry");
        require(registryProxy != address(0), "Need to execute main deploy script first");

        bytes memory bytecode =
            abi.encodePacked(type(KintoAppRegistryV3).creationCode, abi.encode(address(_walletFactory)));

        vm.broadcast(deployerPrivateKey);
        _registryImpl =
            _walletFactory.deployContract{value: 0}(vm.envAddress("LEDGER_ADMIN"), 0, bytecode, bytes32("1"));

        // (2). upgrade registry to new implementation
        _upgradeTo(payable(registryProxy), _registryImpl, deployerPrivateKey);
        _transferOwnership(registryProxy, deployerPrivateKey, vm.envAddress("LEDGER_ADMIN"));
    }

    function upgradeWallet() public returns (address _walletImpl) {
        // (1). deploy new kinto wallet implementation via wallet factory
        bytes memory bytecode = abi.encodePacked(
            type(KintoWalletV4).creationCode,
            abi.encode(
                _getChainDeployment("EntryPoint"),
                IKintoID(_getChainDeployment("KintoID")),
                IKintoAppRegistry(_getChainDeployment("KintoAppRegistry"))
            )
        );

        vm.broadcast(deployerPrivateKey);
        _walletImpl = _walletFactory.deployContract(vm.envAddress("LEDGER_ADMIN"), 0, bytecode, bytes32(0));

        // (2). upgrade all implementations
        vm.broadcast(); // requires LEDGER_ADMIN
        // vm.prank(vm.envAddress("LEDGER_ADMIN"));
        _walletFactory.upgradeAllWalletImplementations(IKintoWallet(_walletImpl));
    }

    function upgradeFactory() public returns (address _factoryImpl) {
        // (1). deploy new kinto factory
        address factoryProxy = _getChainDeployment("KintoWalletFactory");
        require(factoryProxy != address(0), "Need to execute main deploy script first");

        address _walletImpl = _getChainDeployment("KintoWalletV3-impl");
        require(_walletImpl != address(0), "Need to deploy the new wallet first");

        bytes memory bytecode = abi.encodePacked(
            type(KintoWalletFactoryV7).creationCode,
            abi.encode(_walletImpl) // Encoded constructor arguments
        );

        vm.broadcast(deployerPrivateKey);
        _factoryImpl = _walletFactory.deployContract(vm.envAddress("LEDGER_ADMIN"), 0, bytecode, bytes32(0));

        // (2). upgrade factory to new implementation
        vm.broadcast(); // requires LEDGER_ADMIN
        // vm.prank(vm.envAddress("LEDGER_ADMIN"));
        KintoWalletFactory(payable(factoryProxy)).upgradeTo(address(_factoryImpl));
    }

    function upgradeKYCViewer() public returns (address _kycViewerImpl, address _proxy) {
        // make sure kyc viewer proxy is not already deployed
        address viewerProxy = payable(_getChainDeployment("KYCViewer"));
        require(viewerProxy == address(0), "KYCViewer proxy is already deployed");

        // (1). deploy KYCViewerV2 implementation
        bytes memory bytecode = abi.encodePacked(type(KYCViewerV2).creationCode, abi.encode(_walletFactory));

        vm.broadcast(deployerPrivateKey);
        _kycViewerImpl = _walletFactory.deployContract(vm.envAddress("LEDGER_ADMIN"), 0, bytecode, bytes32(0));

        // (2). deploy KYCViewerV2 proxy
        bytecode = abi.encodePacked(type(UUPSProxy).creationCode, abi.encode(address(_kycViewerImpl), ""));

        vm.broadcast(deployerPrivateKey);
        _proxy = _walletFactory.deployContract(vm.envAddress("LEDGER_ADMIN"), 0, bytecode, bytes32(0));

        _initialize(_proxy, deployerPrivateKey);
        _transferOwnership(_proxy, deployerPrivateKey, vm.envAddress("LEDGER_ADMIN"));
    }

    function _upgradeTo(address _proxy, address _newImpl, uint256 _signerPk) internal {
        address payable _from = payable(_getChainDeployment("KintoWallet-admin"));

        // prep upgradeTo user op
        uint256 nonce = IKintoWallet(_from).getNonce();
        uint256[] memory privateKeys = new uint256[](1);
        privateKeys[0] = _signerPk;
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = _createUserOperation(
            block.chainid,
            _from,
            _proxy,
            0,
            nonce,
            privateKeys,
            abi.encodeWithSelector(UUPSUpgradeable.upgradeTo.selector, address(_newImpl)),
            _getChainDeployment("SponsorPaymaster")
        );

        vm.broadcast(deployerPrivateKey);
        IEntryPoint(_getChainDeployment("EntryPoint")).handleOps(userOps, payable(vm.addr(_signerPk)));
    }

    function _initialize(address _proxy, uint256 _signerPk) internal {
        address payable _from = payable(_getChainDeployment("KintoWallet-admin"));

        // fund _proxy in the paymaster
        ISponsorPaymaster _paymaster = ISponsorPaymaster(_getChainDeployment("SponsorPaymaster"));
        vm.broadcast(deployerPrivateKey);
        _paymaster.addDepositFor{value: 0.00000001 ether}(_proxy);
        assertEq(_paymaster.balances(_proxy), 0.00000001 ether);

        // prep upgradeTo user op
        uint256 nonce = IKintoWallet(_from).getNonce();
        uint256[] memory privateKeys = new uint256[](1);
        privateKeys[0] = _signerPk;
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = _createUserOperation(
            block.chainid,
            _from,
            _proxy,
            0,
            nonce,
            privateKeys,
            abi.encodeWithSelector(KYCViewer.initialize.selector),
            _getChainDeployment("SponsorPaymaster")
        );

        vm.broadcast(deployerPrivateKey);
        IEntryPoint(_getChainDeployment("EntryPoint")).handleOps(userOps, payable(vm.addr(_signerPk)));
    }

    function _transferOwnership(address _proxy, uint256 _signerPk, address _newOwner) internal {
        address payable _from = payable(_getChainDeployment("KintoWallet-admin"));

        // prep upgradeTo user op
        uint256 nonce = IKintoWallet(_from).getNonce();
        uint256[] memory privateKeys = new uint256[](1);
        privateKeys[0] = _signerPk;
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = _createUserOperation(
            block.chainid,
            _from,
            _proxy,
            0,
            nonce,
            privateKeys,
            abi.encodeWithSelector(Ownable.transferOwnership.selector, _newOwner),
            _getChainDeployment("SponsorPaymaster")
        );

        vm.broadcast(deployerPrivateKey);
        IEntryPoint(_getChainDeployment("EntryPoint")).handleOps(userOps, payable(vm.addr(_signerPk)));
    }
}
