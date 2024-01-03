// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/KintoID.sol";
import "../src/interfaces/IKintoID.sol";
import "../src/sample/Counter.sol";
import "../src/ETHPriceIsRight.sol";
import "../src/interfaces/IKintoWallet.sol";
import "../src/wallet/KintoWalletFactory.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "../src/paymasters/SponsorPaymaster.sol";
import {ArtifactsReader} from "../test/helpers/ArtifactsReader.sol";
import {UUPSProxy} from "../test/helpers/UUPSProxy.sol";
import {AASetup} from "../test/helpers/AASetup.sol";
import {KYCSignature} from "../test/helpers/KYCSignature.sol";
import {UserOp} from "../test/helpers/UserOp.sol";
import "@aa/core/EntryPoint.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "forge-std/console.sol";

contract KintoWalletFactoryV2 is KintoWalletFactory {
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
        KintoWalletFactoryV2 _implementationV2 =
            new KintoWalletFactoryV2(KintoWallet(payable(_getChainDeployment("KintoWallet-impl"))));
        _oldKintoWalletFactory.upgradeTo(address(_implementationV2));
        console.log("KintoWalletFactory Upgraded to implementation", address(_implementationV2));
        vm.stopBroadcast();
    }
}

contract KintoWalletV3 is KintoWallet {
    constructor(IEntryPoint _entryPoint, IKintoID _kintoIDv1) KintoWallet(_entryPoint, _kintoIDv1) {}
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
        _kintoWalletImpl =
            new KintoWalletV3(IEntryPoint(_getChainDeployment("EntryPoint")), IKintoID(_getChainDeployment("KintoID")));
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
