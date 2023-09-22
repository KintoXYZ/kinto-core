// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/KintoID.sol";
import "../src/interfaces/IKintoID.sol";
import "../src/ETHPriceIsRight.sol";
import "../src/Counter.sol";
import "forge-std/console.sol";
import "../src/wallet/KintoWallet.sol";
import "../src/wallet/KintoWalletFactory.sol";
import "../src/paymasters/SponsorPaymaster.sol";
import '@aa/interfaces/IEntryPoint.sol';
import '@aa/core/EntryPoint.sol';
import {UserOp} from '../test/helpers/UserOp.sol';
import {KYCSignature} from '../test/helpers/KYCSignature.sol';

contract WalletUse is Script, UserOp, KYCSignature {
    KintoWallet _kintoWalletv1;
    KintoWalletFactory _walletFactory;
    SponsorPaymaster _paymaster;
    ETHPriceIsRight _ethpriceisright;
    EntryPoint _entryPoint;
    KintoID _kintoID;
    Counter _counter;

    function setUp() public {}

    function run() public {
        address deployerPublicKey = vm.envAddress('PUBLIC_KEY');
        _kintoID = KintoID(address(0x46180290b99e885b73ADdD43e29f37052cb1b90a));
        _kintoWalletv1 = KintoWallet(payable(0x88576f40100Be4f1c28B6a01D4F281A550ee0849));
        _paymaster = SponsorPaymaster(address(0xcf46A5Ce77D9eC846A986A9cd5B4ce10A85c1C62));
        _ethpriceisright = ETHPriceIsRight(address(0x09fDa0374b837aD7a7C516f5821838e52916A9FB));
        _entryPoint = EntryPoint(payable(0x4Aa975Aaa7B16CB71bf65F13172857803368b383));
        _walletFactory = KintoWalletFactory(address(0xF57E8619f78FBb1Cb78399BA6E69A6639ab62c0C));
        _counter = Counter(address(0xd94c5f155078390F1A00D54B273fF2f32b178c2a));

        uint256 adminPrivateKey = vm.envUint('PRIVATE_KEY');
        uint totalWalletsCreated =  _walletFactory.totalWallets();


        uint startingNonce = _kintoWalletv1.getNonce();
        uint ethpriceisrightPaymasterBalance = _paymaster.balances(address(_ethpriceisright));
        uint kintowalletv1PaymasterBalance = _paymaster.balances(address(_kintoWalletv1));
        uint counterPaymasterBalance = _paymaster.balances(address(_counter));
        
        console.log('startingNonce', startingNonce);
        console.log('kinto wallet entryPoint', address(_kintoWalletv1.entryPoint()));
        console.log('kinto wallet factory wallets', totalWalletsCreated);
        console.log('kinto wallet factory kintoID', address(_walletFactory.kintoID()));
        console.log('kinto wallet factory owner', address(_walletFactory.factoryOwner()));
        console.log('counter contract address', address(_counter));
        console.log('eth price guesses', _ethpriceisright.avgGuess());
        console.log('paymaster balance for ETHPriceIsRight contract:', ethpriceisrightPaymasterBalance);
        console.log('paymaster balance for Kinto wallet 1 contract:', kintowalletv1PaymasterBalance);
        console.log('paymaster balance for Counter contract:', counterPaymasterBalance);

        //uint256 adminPrivateKey = vm.envUint('PRIVATE_KEY');
        
        vm.startBroadcast(adminPrivateKey);
        
        if(!_kintoID.isKYC(deployerPublicKey)) {
            IKintoID.SignatureData memory sigdata = _auxCreateSignature(_kintoID, deployerPublicKey, deployerPublicKey, adminPrivateKey, block.timestamp + 1000);
            uint8[] memory traits = new uint8[](0);
            _kintoID.mintIndividualKyc(sigdata, traits);
        }

        if(totalWalletsCreated==0){
            console.log('this factory has no wallets created');
            IKintoWallet ikw = _walletFactory.createAccount(deployerPublicKey, 12);
            console.log('created wallet', address(ikw));
        }

        if(kintowalletv1PaymasterBalance==0){
            console.log('depositing some eth into the kintowalletv1 account');
            console.log('_kintoWalletv1 address:', address(_kintoWalletv1));
            _paymaster.addDepositFor{value: 0.01 ether}(address(_kintoWalletv1));
        }

        if(ethpriceisrightPaymasterBalance==0){
            console.log('depositing some eth into the ETHPriceIsRight account');
            console.log('_ethpriceisright address:', address(_ethpriceisright));
            _paymaster.addDepositFor{value: 0.01 ether}(address(_ethpriceisright));
        }

        if(counterPaymasterBalance==0){
            console.log('depositing some eth into the Counter account');
            console.log('_ethpriceisright address:', address(_counter));
            _paymaster.addDepositFor{value: 0.01 ether}(address(_counter));
        }

        //Try to make a guess with the admin EOA
        //_ethpriceisright.enterGuess(7000);
        //console.log('eth price guesses (2)', _ethpriceisright.avgGuess());
        //console.log('eth price total guess count', _ethpriceisright.guessCount());

        console.log('Count', _counter.count());
        _counter.increment();
        console.log('Count', _counter.count());

        uint256[] memory privateKeys = new uint256[](1);
        privateKeys[0] = adminPrivateKey;

        /*UserOperation memory userOp = this.createUserOperationWithPaymaster(
            42999, address(_kintoWalletv1), _kintoWalletv1.getNonce(), privateKeys, address(_ethpriceisright), 0,
            abi.encodeWithSignature('enterGuess(uint)', 5000), address(_paymaster));
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = userOp;*/

        UserOperation memory userOp = this.createUserOperationWithPaymaster(
            42999, address(_kintoWalletv1), _kintoWalletv1.getNonce(), privateKeys, address(_counter), 0,
            abi.encodeWithSignature('increment()'), address(_paymaster));
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = userOp;

        _entryPoint.handleOps(userOps, payable(deployerPublicKey));
        //console.log('eth price guesses (3)', _ethpriceisright.avgGuess());
        //console.log('eth price total guess count (2)', _ethpriceisright.guessCount());
        console.log('Count', _counter.count());


        vm.stopBroadcast();
    }

}
