// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import '../src/wallet/KintoWallet.sol';
import '../src/wallet/KintoWalletFactory.sol';
import '../src/paymasters/SponsorPaymaster.sol';
import '../src/KintoID.sol';
import {UserOp} from './helpers/UserOp.sol';
import {UUPSProxy} from './helpers/UUPSProxy.sol';
import {AATestScaffolding} from './helpers/AATestScaffolding.sol';
import {Create2Helper} from './helpers/Create2Helper.sol';

import '@aa/interfaces/IAccount.sol';
import '@aa/interfaces/INonceManager.sol';
import '@aa/interfaces/IEntryPoint.sol';
import '@aa/core/EntryPoint.sol';
import '@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol';
import { UpgradeableBeacon } from '@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol';
import {SignatureChecker} from '@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import '@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol';

import 'forge-std/Test.sol';
import 'forge-std/console.sol';

contract KintoWalletV2 is KintoWallet {
  constructor(IEntryPoint _entryPoint, IKintoID _kintoID) KintoWallet(_entryPoint, _kintoID) {}

  function walletFunction() public pure returns (uint256) {
      return 1;
  }
}

contract Counter {

    uint256 public count;

    constructor() {
      count = 0;
    }

    function increment() public {
        count += 1;
    }
}

contract KintoWalletFactoryV2 is KintoWalletFactory {
  constructor(KintoWallet _impl) KintoWalletFactory(_impl) {

  }
  function newFunction() public pure returns (uint256) {
      return 1;
  }
}

contract KintoWalletFactoryTest is Create2Helper, UserOp, AATestScaffolding {
    using ECDSAUpgradeable for bytes32;
    using SignatureChecker for address;

    KintoWalletFactoryV2 _walletFactoryv2;
    KintoWalletV2 _kintoWalletv2;

    uint256 _chainID = 1;

    address payable _owner = payable(vm.addr(1));
    address _secondowner = address(2);
    address payable _user = payable(vm.addr(3));
    address _user2 = address(4);
    address _upgrader = address(5);
    address _kycProvider = address(6);
    address _recoverer = address(7);
    address payable _funder = payable(vm.addr(8));


    function setUp() public {
        vm.chainId(_chainID);
        vm.startPrank(address(1));
        _owner.transfer(1e18);
        vm.stopPrank();
        deployAAScaffolding(_owner, _kycProvider, _recoverer);
    }

    function testUp() public {
        assertEq(_walletFactory.factoryWalletVersion(), 1);
        assertEq(_entryPoint.walletFactory(), address(_walletFactory));
    }

    /* ============ Upgrade Tests ============ */

    function testOwnerCanUpgradeFactory() public {
        vm.startPrank(_owner);
        KintoWalletFactoryV2 _implementationV2 = new KintoWalletFactoryV2(_kintoWalletImpl);
        _walletFactory.upgradeTo(address(_implementationV2));
        // re-wrap the _proxy
        _walletFactoryv2 = KintoWalletFactoryV2(address(_walletFactory));
        assertEq(_walletFactoryv2.newFunction(), 1);
        vm.stopPrank();
    }

    function testFailOthersCannotUpgradeFactory() public {
        KintoWalletFactoryV2 _implementationV2 = new KintoWalletFactoryV2(_kintoWalletImpl);
        _walletFactory.upgradeTo(address(_implementationV2));
        // re-wrap the _proxy
        _walletFactoryv2 = KintoWalletFactoryV2(address(_proxy));
        assertEq(_walletFactoryv2.newFunction(), 1);
    }

    function testAllWalletsUpgrade() public {
        vm.startPrank(_owner);

        // Deploy wallet implementation
        _kintoWalletImpl = new KintoWalletV2(_entryPoint, _kintoIDv1);

        // deploy walletv1 through wallet factory and initializes it
        _kintoWalletv1 = _walletFactory.createAccount(_owner, _owner, 0);

        // Upgrade all implementations
        _walletFactory.upgradeAllWalletImplementations(_kintoWalletImpl);

        KintoWalletV2 walletV2 = KintoWalletV2(payable(address(_kintoWalletv1)));
        assertEq(walletV2.walletFunction(), 1);
        vm.stopPrank();
    }

    function testFailOthersCannotUpgradeWallets() public {
        // Deploy wallet implementation
        _kintoWalletImpl = new KintoWalletV2(_entryPoint, _kintoIDv1);
        // deploy walletv1 through wallet factory and initializes it
        _kintoWalletv1 = _walletFactory.createAccount(_owner, _owner, 0);
        // Upgrade all implementations
        _walletFactory.upgradeAllWalletImplementations(_kintoWalletImpl);
    }

    /* ============ Deploy Tests ============ */
    function testDeployCustomContract() public {
        // _setPaymasterForContract(address(_kintoWalletv1));
        vm.startPrank(_owner);
        address computed = _walletFactory.getContractAddress(
          bytes32(0), keccak256(abi.encodePacked(type(Counter).creationCode)));
        address created = _walletFactory.deployContract(0,
            abi.encodePacked(type(Counter).creationCode), bytes32(0));
        assertEq(computed, created);
        assertEq(Counter(created).count(), 0);
        Counter(created).increment();
        assertEq(Counter(created).count(), 1);
        vm.stopPrank();
    }

    function testFailCreateWalletThroughDeploy() public {
        vm.prank(_owner);
        bytes memory a = abi.encodeWithSelector(
            KintoWallet.initialize.selector,
            _owner,
            _owner
        );
        _walletFactory.deployContract(
            0,
            abi.encodePacked(
                type(SafeBeaconProxy).creationCode,
                abi.encode(address(0), a)
            ),
            bytes32(0)
        );
        vm.stopPrank();
    }

    function testSignerCanFundWallet() public {
        vm.startPrank(_owner);
        _walletFactory.fundWallet{value: 1e18}(payable(address(_kintoWalletv1)));
        assertEq(address(_kintoWalletv1).balance, 1e18);
    }

    function testWhitelistedSignerCanFundWallet() public {
        _setPaymasterForContract(address(_kintoWalletv1));
        vm.startPrank(_owner);
        uint startingNonce = _kintoWalletv1.getNonce();
        address[] memory funders = new address[](1);
        funders[0] = _funder;
        bool[] memory flags = new bool[](1);
        flags[0] = true;
        uint256[] memory privateKeys = new uint256[](1);
        privateKeys[0] = 1;
        UserOperation memory userOp = this.createUserOperationWithPaymaster(
            _chainID,
            address(_kintoWalletv1), startingNonce, privateKeys, address(_kintoWalletv1), 0,
            abi.encodeWithSignature('setFunderWhitelist(address[],bool[])',funders, flags), address(_paymaster));
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = userOp;
        // Execute the transaction via the entry point
        _entryPoint.handleOps(userOps, payable(_owner));
        vm.startPrank(address(1));
        _funder.transfer(1e17);
        vm.stopPrank();
        vm.startPrank(_funder);
        _walletFactory.fundWallet{value: 1e17}(payable(address(_kintoWalletv1)));
        assertEq(address(_kintoWalletv1).balance, 1e17);
    }

    function testSignerCannotFundInvalidWallet() public {
        vm.startPrank(_owner);
        vm.expectRevert('Invalid wallet or funder');
        _walletFactory.fundWallet{value: 1e18}(payable(address(0)));
    }

    function testRandomSignerCannotFundWallet() public {
        vm.startPrank(address(1));
        _user.transfer(1e18);
        vm.stopPrank();
        vm.startPrank(_user);
        vm.expectRevert('Invalid wallet or funder');
        _walletFactory.fundWallet{value: 1e18}(payable(address(_kintoWalletv1)));
    }

    function testSignerCannotFundWalletWithoutEth() public {
        vm.startPrank(_owner);
        vm.expectRevert('Invalid wallet or funder');
        _walletFactory.fundWallet{value: 0}(payable(address(_kintoWalletv1)));
    }

    /* ============ Helpers ============ */

    function _setPaymasterForContract(address _contract) private {
        vm.startPrank(_owner);
        vm.deal(_owner, 1e20);
        // We add the deposit to the counter contract in the paymaster
        _paymaster.addDepositFor{value: 5e18}(address(_contract));
        vm.stopPrank();
    }
}
