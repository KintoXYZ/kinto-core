// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../src/wallet/KintoWallet.sol";
import "../src/wallet/KintoWalletFactory.sol";

import "@aa/interfaces/IAccount.sol";
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

  //
  function newFunction() public pure returns (uint256) {
      return 1;
  }
}

contract KintoIDTest is Test {
    using ECDSAUpgradeable for bytes32;
    using SignatureChecker for address;

    EntryPoint _entryPoint;
    KintoWalletFactory _walletFactory;

    KintoWallet _kintoWalletv1;
    KintoWalletv2 _kintoWalletv2;

    address _owner = address(1);
    address _secondowner = address(2);
    address _user = vm.addr(3);
    address _user2 = address(4);
    address _upgrader = address(5);

    function setUp() public {
        vm.chainId(1);
        vm.startPrank(_owner);
        _entryPoint = new EntryPoint{salt: 0}();
        console.log('Deployed entry point at', address(_entryPoint));
        //Deploy wallet factory
        _walletFactory = new KintoWalletFactory(_entryPoint);
        console.log('Wallet factory deployed at', address(_walletFactory));
        // deploy walletv1 through wallet factory and initializes it
        _kintoWalletv1 = _walletFactory.createAccount(_owner, 0);
        console.log('wallet deployed at', address(_kintoWalletv1));
        // _kintoIDv1.grantRole(_kintoIDv1.KYC_PROVIDER_ROLE(), _kycProvider);
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

    function testAuthorizedCanUpgrade() public {
        // assertEq(false, _kintoIDv1.hasRole(_kintoIDv1.UPGRADER_ROLE(), _upgrader));
        // vm.startPrank(_owner);
        // _kintoIDv1.grantRole(_kintoIDv1.UPGRADER_ROLE(), _upgrader);
        // vm.stopPrank();
        // // Upgrade from the _upgrader account
        // assertEq(true, _kintoIDv1.hasRole(_kintoIDv1.UPGRADER_ROLE(), _upgrader));
        // KintoIDv2 _implementationV2 = new KintoIDv2();
        // vm.startPrank(_upgrader);
        // _kintoIDv1.upgradeTo(address(_implementationV2));
        // // re-wrap the _proxy
        // _kintoIDv2 = KintoIDv2(address(_proxy));
        // vm.stopPrank();
        // assertEq(_kintoIDv2.newFunction(), 1);
    }

}
