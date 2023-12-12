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

contract KintoSampleCounterDeploy is AASetup,KYCSignature, UserOp{
    using ECDSAUpgradeable for bytes32;
    using SignatureChecker for address;

    KintoID _kintoID;
    EntryPoint _entryPoint;
    KintoWalletFactory _walletFactory;
    SponsorPaymaster _sponsorPaymaster;
    IKintoWallet _newWallet;

    function setUp() public {
      uint256 testPrivateKey = vm.envUint('TEST_PRIVATE_KEY');
      vm.startBroadcast(testPrivateKey);
      (_kintoID, _entryPoint, _walletFactory, _sponsorPaymaster) = _checkAccountAbstraction();
      vm.stopBroadcast();
    }

    function run() public {
      console.log('All AA setup is correct');
      uint256 testPrivateKey = vm.envUint('TEST_PRIVATE_KEY');
      address testPublicKey = vm.envAddress('TEST_PUBLIC_KEY');

      vm.startBroadcast(testPrivateKey);

      //STEP 1: Fetching wallet
      uint salt = 0;
      address newWallet = _walletFactory.getAddress(testPublicKey, testPublicKey, salt);
      if (!isContract(newWallet)) {
          console.log('ERROR: Wallet not deployed for owner', testPublicKey, 'at', newWallet);
          revert();
      }
      _newWallet = IKintoWallet(newWallet);
      console.log("Using wallet: ", address(_newWallet));

      //STEP 2: Deploy contract (using the wallet factory deployContract function)
      address computed = _walletFactory.getContractAddress(
          bytes32(0), keccak256(abi.encodePacked(type(Counter).creationCode))); //if you need to deploy a new Counter edit the bytes32(0) (salt)
      if (!isContract(computed)) {
          address created = _walletFactory.deployContract(0,
              abi.encodePacked(type(Counter).creationCode), bytes32(0));
          console.log('Deployed Counter contract at', created);
      } else {
          console.log('Counter already deployed at', computed);
      }      

      //STEP 3: Add deposit to the paymaster if low, in kinto all ops are paid by the Sponsor paymaster
      if (_sponsorPaymaster.balances(computed) <= 1e14) {
          _sponsorPaymaster.addDepositFor{value: 5e16}(computed);
          console.log('Adding paymaster balance to counter', computed);
      } else {
          console.log('Counter already has balance to pay for tx', computed);
      }

      //STEP 4: Create an AA UserOp
      Counter counter = Counter(computed);
      uint startingNonce = _newWallet.getNonce();
      uint256[] memory privateKeys = new uint256[](1);
      privateKeys[0] = testPrivateKey;
      UserOperation memory userOp = this.createUserOperationWithPaymasterCustomGas(
          block.chainid,
          address(_newWallet),
          startingNonce,
          privateKeys,
          address(counter),
          0,
          abi.encodeWithSignature('increment()'),
          address(_sponsorPaymaster),
          [uint256(5000000), 3, 3]
      );
      UserOperation[] memory userOps = new UserOperation[](1);
      userOps[0] = userOp;

      //STEP 5: Execute a UserOp via the Kinto EntryPoint
      console.log('Before UserOp. Counter:', counter.count());
      _entryPoint.handleOps(userOps, payable(testPublicKey));
      console.log('After UserOp. Counter:', counter.count()); 

      vm.stopBroadcast();
    }
}