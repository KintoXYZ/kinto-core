// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../src/wallet/KintoWallet.sol";
import "../src/wallet/KintoWalletFactory.sol";
import {UserOpTest} from './helpers/UserOpTest.sol';

import "@aa/interfaces/IAccount.sol";
import "@aa/interfaces/INonceManager.sol";
import "@aa/interfaces/IEntryPoint.sol";
import "@aa/core/EntryPoint.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "forge-std/Test.sol";
import "forge-std/console.sol";

contract KintoWalletv2 is KintoWallet {
  constructor(IEntryPoint _entryPoint) KintoWallet(_entryPoint) {}

  function newFunction() public pure returns (uint256) {
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

contract KintoIDTest is UserOpTest {
    using ECDSAUpgradeable for bytes32;
    using SignatureChecker for address;

    EntryPoint _entryPoint;
    KintoWalletFactory _walletFactory;

    KintoWallet _kintoWalletv1;
    KintoWalletv2 _kintoWalletv2;

    uint256 chainID = 1;

    address payable _owner = payable(vm.addr(1));
    address _secondowner = address(2);
    address _user = vm.addr(3);
    address _user2 = address(4);
    address _upgrader = address(5);

    function setUp() public {
        vm.chainId(chainID);
        vm.startPrank(address(1));
        _owner.transfer(1e18);
        vm.stopPrank();
        vm.startPrank(_owner);
        _entryPoint = new EntryPoint{salt: 0}();
        console.log('Deployed entry point at', address(_entryPoint));
        //Deploy wallet factory
        _walletFactory = new KintoWalletFactory(_entryPoint);
        console.log('Wallet factory deployed at', address(_walletFactory));
        // deploy walletv1 through wallet factory and initializes it
        _kintoWalletv1 = _walletFactory.createAccount(_owner, 0);
        console.log('wallet deployed at', address(_kintoWalletv1));
        vm.stopPrank();
    }

    function testUp() public {
        assertEq(address(_kintoWalletv1.entryPoint()), address(_entryPoint));
        assertEq(_kintoWalletv1.owners(0), _owner);
    }

    // Upgrade Tests

    function testOwnerCanUpgrade() public {
        vm.startPrank(_owner);
        KintoWalletv2 _implementationV2 = new KintoWalletv2(_entryPoint);
        _kintoWalletv1.upgradeTo(address(_implementationV2));
        _kintoWalletv2 = KintoWalletv2(payable(_kintoWalletv1));
        assertEq(_kintoWalletv2.newFunction(), 1);
        vm.stopPrank();
    }

    function testFailOthersCannotUpgrade() public {
        KintoWalletv2 _implementationV2 = new KintoWalletv2(_entryPoint);
        _kintoWalletv1.upgradeTo(address(_implementationV2));
    }

    function testSimpleTransactionAfterDeposit() public {
        vm.startPrank(_owner);
        // We add the deposit in the entry point
        _kintoWalletv1.addDeposit{value: 1e15}();
        // Let's deploy the counter contract
        Counter counter = new Counter();
        assertEq(counter.count(), 0);
        // Let's send a transaction to the counter contract through our wallet
        UserOperation memory userOp = this.createUserOperation(address(_kintoWalletv1), 1, address(counter), abi.encodeWithSignature("increment()"));
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = userOp;
        // Execute the transaction via the entry point
        _entryPoint.handleOps(userOps, payable(_owner));
        assertEq(counter.count(), 1);
        vm.stopPrank();
    }

}
