// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import 'forge-std/Script.sol';
import '../src/KintoID.sol';
import '../src/interfaces/IKintoID.sol';
import '../src/sample/Counter.sol';
import '../src/ETHPriceIsRight.sol';
import '../src/interfaces/IKintoWallet.sol';
import '../src/wallet/KintoWalletFactory.sol';
import '../src/paymasters/SponsorPaymaster.sol';
import { Create2Helper } from '../test/helpers/Create2Helper.sol';
import { UUPSProxy } from '../test/helpers/UUPSProxy.sol';
import { AASetup } from '../test/helpers/AASetup.sol';
import { KYCSignature } from '../test/helpers/KYCSignature.sol';
import { UserOp } from '../test/helpers/UserOp.sol';
import '@aa/core/EntryPoint.sol';
import '@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol';
import { SignatureChecker } from '@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import '@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol';
import 'forge-std/console.sol';

contract KintoWalletFactoryUpgradeScript is Script {

    using ECDSAUpgradeable for bytes32;
    using SignatureChecker for address;

    KintoWalletFactory _implementation;
    KintoWalletFactory _oldKintoWalletFactory;

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint('PRIVATE_KEY');
        vm.startBroadcast(deployerPrivateKey);
        // KintoWalletFactoryV2 _implementationV2 = new KintoWalletFactoryV2(_beacon);
        // _oldKintoWalletFactory.upgradeTo(address(_implementationV2));
        // console.log('KintoWalletFactory Upgraded to implementation', address(_implementationV2));
        vm.stopBroadcast();
    }
}

contract KintoWalletsUpgradeScript is Script {

    using ECDSAUpgradeable for bytes32;
    using SignatureChecker for address;

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint('PRIVATE_KEY');
        vm.startBroadcast(deployerPrivateKey);
        // Deploy new wallet implementation
        // _kintoWalletImpl = new KintoWalletV2(_entryPoint, _kintoIDv1);
        // // deploy walletv1 through wallet factory and initializes it
        // _kintoWalletv1 = _walletFactory.createAccount(_owner, _owner, 0);
        // // Upgrade all implementations
        // _walletFactory.upgradeAllWalletImplementations(_kintoWalletImpl);
        vm.stopBroadcast();
    }
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
        // console.log('address proxy', vm.envAddress('ID_PROXY_ADDRESS'));
        // _oldKinto = KintoID(payable(vm.envAddress('ID_PROXY_ADDRESS')));
        // KintoIDV2 implementationV2 = new KintoIDV2();
        // _oldKinto.upgradeTo(address(implementationV2));
        // console.log('KintoID upgraded to implementation', address(implementationV2));
        vm.stopBroadcast();
    }

}