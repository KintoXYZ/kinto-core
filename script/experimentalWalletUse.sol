// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/KintoID.sol";
import "../src/interfaces/IKintoID.sol";
import "../src/ETHPriceIsRight.sol";
import "forge-std/console.sol";
import "../src/wallet/KintoWallet.sol";
import "../src/paymasters/SponsorPaymaster.sol";
import '@aa/interfaces/IEntryPoint.sol';
import '@aa/core/EntryPoint.sol';
import {UserOp} from '../test/helpers/UserOp.sol';

contract ExperimentalWalletUse is Script, UserOp {
    KintoWallet _kintoWalletv1;
    SponsorPaymaster _paymaster;
    ETHPriceIsRight _ethpriceisright;
    EntryPoint _entryPoint;
    uint256[] private privateKeysStorage;

    function setUp() public {}

    function run() public {
        _kintoWalletv1 = KintoWallet(payable(0x42e94e29ed7370ad98497D9398f79C203e72195f));
        _paymaster = SponsorPaymaster(address(0xef81934A2B6edDB02F4E7C641A8CF2A206c7A513));
        _ethpriceisright = ETHPriceIsRight(address(0xD6b17c41ffd64bB4B922Cbc26b41e3E3AEE4f806));
        _entryPoint = EntryPoint(payable(0x7aD823A5cA21768a3D3041118Bc6e981B0e4D5ee));
        _walletFactory = KintoWalletFactory(address(0x5d7715A10d22Dc04400eb47D8f776a72b39F9716));
        uint startingNonce = _kintoWalletv1.getNonce();
        console.log('startingNonce', startingNonce);
        console.log('kinto wallet entryPoint', address(_kintoWalletv1.entryPoint()));
        console.log('kinto wallet factory wallets', _walletFactory.totalWallets());
        console.log('eth price guesses', _ethpriceisright.avgGuess());
        console.log('paymaster balance guesses', _paymaster.balances(address(_ethpriceisright)));
        uint256 adminPrivateKey = vm.envUint('PRIVATE_KEY');
        vm.startBroadcast(adminPrivateKey);
        
        uint256[] memory privateKeys = new uint256[](1);
        privateKeys[0] = adminPrivateKey;

        UserOperation memory userOp = this.createUserOperationWithPaymaster(
            address(_kintoWalletv1), startingNonce, privateKeys, address(_ethpriceisright), 0,
            abi.encodeWithSignature('enterGuess(uint)', 5000), address(_paymaster));
        _ethpriceisright.enterGuess(7000);
        console.log('eth price guesses 2', _ethpriceisright.avgGuess());
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = userOp;

        _entryPoint.handleOps(userOps, payable(0x1dBDF0936dF26Ba3D7e4bAA6297da9FE2d2428c2));
        console.log('eth price guesses 3', _ethpriceisright.avgGuess());

        vm.stopBroadcast();
    }

}
