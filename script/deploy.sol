// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import 'forge-std/Script.sol';
import '../src/KintoID.sol';
import '../src/interfaces/IKintoID.sol';
import '../src/interfaces/IKintoWallet.sol';
import '../src/wallet/KintoWalletFactory.sol';
import '../src/paymasters/SponsorPaymaster.sol';
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

contract KintoIDV2 is KintoID {
  constructor() KintoID() {}
}

contract KintoIDUpgradeScript is Script {

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

contract KintoInitialDeployScript is Script {
    using ECDSAUpgradeable for bytes32;
    using SignatureChecker for address;

    /* solhint-disable var-name-mixedcase */
    /* solhint-disable private-vars-leading-underscore */
    address CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    KintoWalletFactory _walletFactory;
    EntryPoint _entryPoint;
    SponsorPaymaster _sponsorPaymaster;
    KintoID _implementation;
    KintoID _kintoIDv1;
    UUPSProxy _proxy;
    IKintoWallet _kintoWalletv1;

    /// @notice Precompute a contract address deployed via CREATE2
    function computeAddress(uint256 salt, bytes memory creationCode) public view returns (address) {

        return address(
            uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), CREATE2_DEPLOYER, salt, keccak256(creationCode)))))
        );
    }

    function isContract(address _addr) private view returns (bool){
        uint32 size;
        assembly {
            size := extcodesize(_addr)
        }
        return (size > 0);
    }


    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint('PRIVATE_KEY');
        vm.startBroadcast(deployerPrivateKey);
        // Kinto ID
        address kintoIDImplAddr = computeAddress(0,
            abi.encodePacked(type(KintoID).creationCode));
        if (isContract(kintoIDImplAddr)) {
            _implementation = KintoID(payable(kintoIDImplAddr));
            console.log('Already deployed Kinto ID implementation at', address(kintoIDImplAddr));
        } else {
            // Deploy Kinto ID implementation
            _implementation = new KintoID{ salt: 0 }();
            console.log('Kinto ID implementation deployed at', address(_implementation));
        }
        address kintoProxyAddr = computeAddress(
            0, abi.encodePacked(type(UUPSProxy).creationCode,
            abi.encode(address(_implementation), '')));
        if (isContract(kintoProxyAddr)) {
            _proxy = UUPSProxy(payable(kintoProxyAddr));
            console.log('Already deployed Kinto ID proxy at', address(kintoProxyAddr));
            _kintoIDv1 = KintoID(address(_proxy));
        } else {
            // deploy proxy contract and point it to implementation
            _proxy = new UUPSProxy{salt: 0}(address(_implementation), '');
            // wrap in ABI to support easier calls
            _kintoIDv1 = KintoID(address(_proxy));
            console.log('Kinto ID proxy deployed at ', address(_kintoIDv1));
            // Initialize proxy
            _kintoIDv1.initialize();
        }
        _kintoIDv1 = KintoID(address(_proxy));

        // Entry Point
        address entryPointAddr = computeAddress(0, abi.encodePacked(type(EntryPoint).creationCode));
        // Check Entry Point
        if (isContract(entryPointAddr)) {
            _entryPoint = EntryPoint(payable(entryPointAddr));
            console.log('Entry Point already deployed at', address(_entryPoint));
        } else {
            // Deploy Entry point
            _entryPoint = new EntryPoint{salt: 0}();
            console.log('Entry point deployed at', address(_entryPoint));
        }

        // Check Wallet Factory
        address walletFactoryAddr = computeAddress(0,
            abi.encodePacked(type(KintoWalletFactory).creationCode,
            abi.encode(address(_entryPoint), address(_kintoIDv1))));
        if (isContract(walletFactoryAddr)) {
            _walletFactory = KintoWalletFactory(payable(walletFactoryAddr));
            console.log('Wallet factory already deployed at', address(_walletFactory));
        } else {
            //Deploy wallet factory
            _walletFactory = new KintoWalletFactory{salt: 0}(_entryPoint, _kintoIDv1);
            console.log('Wallet factory deployed at', address(_walletFactory));
        }

        address walletFactory = EntryPoint(payable(entryPointAddr)).walletFactory();
        if (walletFactory == address(0)) {
            // Set Wallet Factory in entry point
            _entryPoint.setWalletFactory(address(_walletFactory));
            console.log('Wallet factory set in entry point', _entryPoint.walletFactory());

        } else {
            if (walletFactory != walletFactoryAddr) {
                console.log('WARN: Wallet Factory & Entry Point do not match');
            } else {
                console.log('Wallet factory already deployed and set in entry point', walletFactory);
            }
        }

        // Sponsor Paymaster
        bytes memory creationCodePaymaster = abi.encodePacked(
            type(SponsorPaymaster).creationCode, abi.encode(address(_entryPoint)));
        address paymasterAddr = computeAddress(0, creationCodePaymaster);
        // Check Paymaster
        if (isContract(paymasterAddr)) {
            console.log('Paymaster already deployed at', address(paymasterAddr));
        } else {
            // Deploy Entry point
            _sponsorPaymaster = new SponsorPaymaster{salt: 0}(IEntryPoint(address(_entryPoint)));
            console.log('Sponsor paymaster deployed at', address(_sponsorPaymaster));
        }

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