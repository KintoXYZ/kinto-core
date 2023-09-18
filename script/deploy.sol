// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import 'forge-std/Script.sol';
import '../src/KintoID.sol';
import '../src/interfaces/IKintoID.sol';
import '../src/interfaces/IKintoWallet.sol';
import '../src/wallet/KintoWalletFactory.sol';
import '@aa/core/EntryPoint.sol';
import '@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol';
import { SignatureChecker } from '@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import '@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol';
import 'forge-std/console.sol';


contract UUPSProxy is ERC1967Proxy {
    constructor(address _implementation, bytes memory _data)
        ERC1967Proxy(_implementation, _data)
    {}
}

contract KintoInitialDeployScript is Script {

    using ECDSAUpgradeable for bytes32;
    using SignatureChecker for address;

    KintoID _implementation;
    KintoID _kintoIDv1;
    UUPSProxy _proxy;

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint('PRIVATE_KEY');
        vm.startBroadcast(deployerPrivateKey);
        _implementation = new KintoID();
        // deploy proxy contract and point it to implementation
        _proxy = new UUPSProxy(address(_implementation), '');
        // wrap in ABI to support easier calls
        _kintoIDv1 = KintoID(address(_proxy));
        // Initialize proxy
        _kintoIDv1.initialize();
        vm.stopBroadcast();
    }
}

contract KintoIDV2 is KintoID {
  constructor() KintoID() {}
}

contract KintoUpgradeScript is Script {

    using ECDSAUpgradeable for bytes32;
    using SignatureChecker for address;

    KintoID _implementation;
    KintoID _oldKinto;

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint('PRIVATE_KEY');
        vm.startBroadcast(deployerPrivateKey);
        console.log('address proxy', vm.envAddress('ID_PROXY_ADDRESS'));
        _oldKinto = KintoID(payable(vm.envAddress('ID_PROXY_ADDRESS')));
        console.log(_oldKinto.name());
        console.log('deploying new implementation');
        KintoIDV2 implementationV2 = new KintoIDV2();
        console.log('before upgrade');
        _oldKinto.upgradeTo(address(implementationV2));
        // re-wrap the proxy
        console.log('upgraded');
        vm.stopBroadcast();
    }

}

contract KintoAAInitialDeployScript is Script {
    using ECDSAUpgradeable for bytes32;
    using SignatureChecker for address;

    KintoWalletFactory _walletFactory;
    EntryPoint _entryPoint;

    IKintoWallet _kintoWalletv1;

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint('PRIVATE_KEY');
        vm.startBroadcast(deployerPrivateKey);
        // Create Entry Point
        _entryPoint = new EntryPoint{salt: 0}();
        console.log('Entry point deployed at', address(_entryPoint));
        //Deploy wallet factory
        _walletFactory = new KintoWalletFactory{salt: 0}(_entryPoint, IKintoID(vm.envAddress('ID_PROXY_ADDRESS')));
        console.log('Wallet factory deployed at', address(_walletFactory));
        // Set Wallet Factory in entry point
        _entryPoint.setWalletFactory(address(_walletFactory));
        console.log('Wallet factory set in entry point', _entryPoint.walletFactory());
        // address deployerPublicKey = vm.envAddress('PUBLIC_KEY');
        //_kintoWalletv1 = _walletFactory.createAccount(deployerPublicKey, 0);
        // console.log('wallet deployed at', address(_kintoWalletv1));
        vm.stopBroadcast();
    }
}


contract KintoWalletv2 is KintoWallet {
  constructor(IEntryPoint _entryPoint, IKintoID _kintoID) KintoWallet(_entryPoint, _kintoID) {}

  function newFunction() public pure returns (uint256) {
      return 1;
  }
}

contract KintoWalletUpgradeScript is Script {

    using ECDSAUpgradeable for bytes32;
    using SignatureChecker for address;

    IEntryPoint _entryPoint = IEntryPoint(0xB8E2e62b4d44EB2bd39d75FDF6de124b5f95F1Af);
    KintoWallet _implementation;
    KintoWallet _oldKinto;

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint('PRIVATE_KEY');
        vm.startBroadcast(deployerPrivateKey);
        _oldKinto = KintoWallet(payable(vm.envAddress('WALLET_ADDRESS')));
        console.log('deploying new implementation');
        KintoWalletv2 implementationV2 = new KintoWalletv2(_entryPoint, IKintoID(vm.envAddress('ID_PROXY_ADDRESS')));
        console.log('before upgrade');
        _oldKinto.upgradeTo(address(implementationV2));
        console.log('upgraded');
        vm.stopBroadcast();
    }
}