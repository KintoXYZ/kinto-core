// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../src/wallet/KintoWallet.sol";
import "../src/wallet/KintoWalletFactory.sol";

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

abstract contract UserOpTest is Test {
    using ECDSAUpgradeable for bytes32;

    function packUserOp (UserOperation memory op, bool forSig) internal pure returns (bytes memory) {
      if (forSig) {
        return abi.encode(
          op.sender,
          op.nonce,
          keccak256(op.initCode),
          keccak256(op.callData),
          op.callGasLimit,
          op.verificationGasLimit,
          op.preVerificationGas,
          op.maxFeePerGas,
          op.maxPriorityFeePerGas,
          keccak256(op.paymasterAndData)
        );
      }
      return abi.encode(
        op.sender,
        op.nonce,
        op.initCode,
        op.callData,
        op.callGasLimit,
        op.verificationGasLimit,
        op.preVerificationGas,
        op.maxFeePerGas,
        op.maxPriorityFeePerGas,
        op.paymasterAndData,
        op.signature
      );
    }

    function getUserOpHash (UserOperation memory op, IEntryPoint _entryPoint, uint256 chainID) internal pure returns (bytes32) {
      bytes32 opHash = keccak256(packUserOp(op, true));
      return keccak256(
        abi.encode(
          opHash,
          address(_entryPoint),
          chainID
        )
      );
    }

    function signUserOp (UserOperation memory op, IEntryPoint _entryPoint, uint256 chainID, uint256 privateKey) internal pure returns (bytes memory) {
      bytes32 hash = getUserOpHash(op, _entryPoint, chainID);
      hash = hash.toEthSignedMessageHash();
      (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, hash);
      bytes memory signature = abi.encodePacked(r, s, v);
      return signature;
    }
    
    // 'address', // sender
    // 'uint256', // nonce
    // 'bytes32', // initCode
    // 'bytes32', // callData
    // 'uint256', // callGasLimit
    // 'uint256', // verificationGasLimit
    // 'uint256', // preVerificationGas
    // 'uint256', // maxFeePerGas
    // 'uint256', // maxPriorityFeePerGas
    // 'bytes32' // paymasterAndData
    function createUserOperation(address _account, uint256 _privateKeyOwner) public view returns (UserOperation memory op) {
      op = UserOperation({
        sender: _account,
        nonce: KintoWallet(payable(_account)).getNonce(),
        initCode: bytes(""),
        callData: bytes(""),
        callGasLimit: 0,
        verificationGasLimit: 150000, // default verification gas. will add create2 cost (3200+200*length) if initCode exists
        preVerificationGas: 21000, // should also cover calldata cost.
        maxFeePerGas: 0,
        maxPriorityFeePerGas: 1e9,
        paymasterAndData: bytes(""),
        signature: bytes("")
      });
      op.signature = signUserOp(op, KintoWallet(payable(_account)).entryPoint(), 1, _privateKeyOwner);
      return op;
    }
}

contract KintoWalletv2 is KintoWallet {
  constructor(IEntryPoint _entryPoint) KintoWallet(_entryPoint) {}

  //
  function newFunction() public pure returns (uint256) {
      return 1;
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

    address _owner = address(1);
    address _secondowner = address(2);
    address _user = vm.addr(3);
    address _user2 = address(4);
    address _upgrader = address(5);

    function setUp() public {
        vm.chainId(chainID);
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
