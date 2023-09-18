// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/KintoID.sol";
import "../src/interfaces/IKintoID.sol";
import "../src/ETHPriceIsRight.sol";
import "forge-std/console.sol";
import "../src/wallet/KintoWallet.sol";
import "../src/wallet/KintoWalletFactory.sol";
import "../src/paymasters/SponsorPaymaster.sol";
import '@aa/interfaces/IEntryPoint.sol';
import '@aa/core/EntryPoint.sol';
import {UserOp} from '../test/helpers/UserOp.sol';

contract WalletUse is Script, UserOp {
    KintoWallet _kintoWalletv1;
    KintoWalletFactory _walletFactory;
    SponsorPaymaster _paymaster;
    ETHPriceIsRight _ethpriceisright;
    EntryPoint _entryPoint;

    function setUp() public {}

    function run() public {
        address deployerPublicKey = vm.envAddress('PUBLIC_KEY');
        _kintoWalletv1 = KintoWallet(payable(0xD791AaF573F888480c6Ec42813f801445c247596));
        _paymaster = SponsorPaymaster(address(0xbe3D3EAec911aA3F90428ac6B4F556449ee2c3d9));
        _ethpriceisright = ETHPriceIsRight(address(0x09fDa0374b837aD7a7C516f5821838e52916A9FB));
        _entryPoint = EntryPoint(payable(0x37435d14f8fBbd693997Ec3ec0Db3a96D4cAF186));
        _walletFactory = KintoWalletFactory(address(0x4DB6ed90F380DB04C1b454C27D96375b2dcEd95A));

        uint totalWalletsCreated =  _walletFactory.totalWallets();

        uint startingNonce = _kintoWalletv1.getNonce();
        uint ethpriceisrightPaymasterBalance = _paymaster.balances(address(_ethpriceisright));
        uint kintowalletv1PaymasterBalance = _paymaster.balances(address(_kintoWalletv1));

        console.log('startingNonce', startingNonce);
        console.log('kinto wallet entryPoint', address(_kintoWalletv1.entryPoint()));
        console.log('kinto wallet factory wallets', totalWalletsCreated);
        console.log('kinto wallet factory kintoID', address(_walletFactory.kintoID()));
        console.log('kinto wallet factory owner', address(_walletFactory.factoryOwner()));
        console.log('eth price guesses', _ethpriceisright.avgGuess());
        console.log('paymaster balance for ETHPriceIsRight contract:', ethpriceisrightPaymasterBalance);
        console.log('paymaster balance for Kinto wallet 1 contract:', kintowalletv1PaymasterBalance);

        uint256 adminPrivateKey = vm.envUint('PRIVATE_KEY');
        
        vm.startBroadcast(adminPrivateKey);
        
        if(totalWalletsCreated==0){
            console.log('this factory has no wallets created');
            IKintoWallet ikw = _walletFactory.createAccount(deployerPublicKey, 0);
            console.log('created wallet', address(ikw));
        }

        if(kintowalletv1PaymasterBalance==0){
            console.log('depositing some eth into the kintowalletv1 account');
            console.log('_kintoWalletv1 address:', address(_kintoWalletv1));
            _paymaster.addDepositFor{value: 0.1 ether}(address(_kintoWalletv1));
        }

        if(ethpriceisrightPaymasterBalance==0){
            console.log('depositing some eth into the ETHPriceIsRight account');
            console.log('_ethpriceisright address:', address(_ethpriceisright));
            _paymaster.addDepositFor{value: 0.1 ether}(address(_ethpriceisright));
        }

        //Try to make a guess with the admin EOA
        //_ethpriceisright.enterGuess(7000);
        console.log('eth price guesses (2)', _ethpriceisright.avgGuess());
        console.log('eth price total guess count', _ethpriceisright.guessCount());


        uint256[] memory privateKeys = new uint256[](1);
        privateKeys[0] = adminPrivateKey;

        UserOperation memory userOp = this.createUserOperationWithPaymaster(
            42999, address(_kintoWalletv1), _kintoWalletv1.getNonce(), privateKeys, address(_ethpriceisright), 0,
            abi.encodeWithSignature('enterGuess(uint)', 5000), address(_paymaster));
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = userOp;

        _entryPoint.handleOps{gas: 0.1 ether}(userOps, payable(deployerPublicKey));
        console.log('eth price guesses (3)', _ethpriceisright.avgGuess());
        console.log('eth price total guess count (2)', _ethpriceisright.guessCount());


        vm.stopBroadcast();
    }

}
