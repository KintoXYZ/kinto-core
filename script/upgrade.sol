// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "@aa/core/EntryPoint.sol";

import "../src/KintoID.sol";
import "../src/wallet/KintoWallet.sol";
import "../src/interfaces/IKintoID.sol";
import "../src/wallet/KintoWalletFactory.sol";

import "../test/helpers/ArtifactsReader.sol";

import "forge-std/Script.sol";
import "forge-std/console.sol";

contract KintoWalletFactoryUpgrade is KintoWalletFactory {
    constructor(KintoWallet _impl) KintoWalletFactory(_impl) {}
}

contract KintoWalletFactoryUpgradeScript is ArtifactsReader {
    using ECDSAUpgradeable for bytes32;
    using SignatureChecker for address;

    KintoWalletFactory _implementation;
    KintoWalletFactory _oldKintoWalletFactory;

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        _oldKintoWalletFactory = KintoWalletFactory(payable(_getChainDeployment("KintoWalletFactory")));
        KintoWalletFactoryUpgrade _newImplementation =
            new KintoWalletFactoryUpgrade(KintoWallet(payable(_getChainDeployment("KintoWallet-impl"))));
        _oldKintoWalletFactory.upgradeTo(address(_newImplementation));
        console.log("KintoWalletFactory Upgraded to implementation", address(_newImplementation));
        vm.stopBroadcast();
    }
}

contract KintoWalletVTest is KintoWallet {
    constructor(IEntryPoint _entryPoint, IKintoID _kintoIDv1, IKintoAppRegistry _kintoApp)
        KintoWallet(_entryPoint, _kintoIDv1, _kintoApp)
    {}
}

contract KintoWalletsUpgradeScript is ArtifactsReader {
    using ECDSAUpgradeable for bytes32;
    using SignatureChecker for address;

    KintoWalletFactory _walletFactory;
    KintoWallet _kintoWalletImpl;

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        _walletFactory = KintoWalletFactory(payable(_getChainDeployment("KintoWalletFactory")));
        // Deploy new wallet implementation
        _kintoWalletImpl = new KintoWalletVTest(
            IEntryPoint(_getChainDeployment("EntryPoint")),
            IKintoID(_getChainDeployment("KintoID")),
            IKintoAppRegistry(_getChainDeployment("IKintoAppRegistry"))
        );
        // // Upgrade all implementations
        _walletFactory.upgradeAllWalletImplementations(_kintoWalletImpl);
        vm.stopBroadcast();
    }
}

contract KintoIDV2 is KintoID {
    constructor() KintoID() {}
}

contract KintoIDUpgradeScript is ArtifactsReader {
    using ECDSAUpgradeable for bytes32;
    using SignatureChecker for address;

    KintoID _implementation;
    KintoID _oldKinto;

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        _oldKinto = KintoID(payable(_getChainDeployment("KintoID")));
        // Replace this with the contract name of the new implementation
        KintoIDV2 implementationV2 = new KintoIDV2();
        _oldKinto.upgradeTo(address(implementationV2));
        console.log("KintoID upgraded to implementation", address(implementationV2));
        vm.stopBroadcast();
    }
}
