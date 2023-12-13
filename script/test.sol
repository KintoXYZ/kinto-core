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

contract KintoDeployTestWalletScript is AASetup, KYCSignature {

    using ECDSAUpgradeable for bytes32;
    using SignatureChecker for address;

    KintoID _kintoID;
    EntryPoint _entryPoint;
    KintoWalletFactory _walletFactory;
    SponsorPaymaster _sponsorPaymaster;
    IKintoWallet _newWallet;

    function setUp() public {
        uint256 deployerPrivateKey = vm.envUint('PRIVATE_KEY');
        vm.startBroadcast(deployerPrivateKey);
        (_kintoID, _entryPoint, _walletFactory, _sponsorPaymaster) = _checkAccountAbstraction();
        vm.stopBroadcast();
    }

    function run() public {
        uint256 deployerPrivateKey = vm.envUint('PRIVATE_KEY');
        address recipientWallet = vm.envAddress('TEST_PUBLIC_KEY');
        uint256 recipientKey = vm.envUint('TEST_PRIVATE_KEY');
        
        console.log('All AA setup is correct');
        uint totalWalletsCreated =  _walletFactory.totalWallets();
        vm.startBroadcast(deployerPrivateKey);
        if(!_kintoID.isKYC(recipientWallet)) {
            IKintoID.SignatureData memory sigdata = _auxCreateSignature(
                _kintoID, recipientWallet,
                recipientWallet,
                recipientKey, block.timestamp + 1000);
            uint16[] memory traits = new uint16[](0);
            _kintoID.mintIndividualKyc(sigdata, traits);
        }

        console.log('This factory has', totalWalletsCreated, ' created');
        uint salt = 0;
        address newWallet = _walletFactory.getAddress(recipientWallet, recipientWallet, salt);
        if (isContract(newWallet)) {
            console.log('Wallet already deployed for owner', recipientWallet, 'at', newWallet);
        } else {
            IKintoWallet ikw = _walletFactory.createAccount(recipientWallet, recipientWallet, salt);
            console.log('Created wallet', address(ikw));
            console.log('Total Wallets:', _walletFactory.totalWallets());
        }
        vm.stopBroadcast();
    }
}

contract KintoDeployTestAddressWalletScript is AASetup, KYCSignature {

    using ECDSAUpgradeable for bytes32;
    using SignatureChecker for address;

    KintoID _kintoID;
    EntryPoint _entryPoint;
    KintoWalletFactory _walletFactory;
    SponsorPaymaster _sponsorPaymaster;
    IKintoWallet _newWallet;

    function setUp() public {
        uint256 deployerPrivateKey = vm.envUint('PRIVATE_KEY');
        vm.startBroadcast(deployerPrivateKey);
        (_kintoID, _entryPoint, _walletFactory, _sponsorPaymaster) = _checkAccountAbstraction();
        vm.stopBroadcast();
    }

    function run() public {
        uint256 deployerPrivateKey = vm.envUint('PRIVATE_KEY');
        address testPublicKey = vm.envAddress('TEST_PUBLIC_KEY');
        uint256 testPrivateKey = vm.envUint('TEST_PRIVATE_KEY');
        console.log('All AA setup is correct');
        uint totalWalletsCreated =  _walletFactory.totalWallets();
        vm.startBroadcast(deployerPrivateKey);
        if(!_kintoID.isKYC(testPublicKey)) {
            IKintoID.SignatureData memory sigdata = _auxCreateSignature(
                _kintoID, testPublicKey,
                testPublicKey,
                testPrivateKey, block.timestamp + 1000);
            uint16[] memory traits = new uint16[](0);
            _kintoID.mintIndividualKyc(sigdata, traits);
        }

        console.log('This factory has', totalWalletsCreated, ' created');
        uint salt = 0;
        address newWallet = _walletFactory.getAddress(testPublicKey, testPublicKey, salt);
        if (isContract(newWallet)) {
            console.log('Wallet already deployed for owner', testPublicKey, 'at', newWallet);
        } else {
            IKintoWallet ikw = _walletFactory.createAccount(testPublicKey, testPublicKey, salt);
            console.log('Created wallet', address(ikw));
            console.log('Total Wallets:', _walletFactory.totalWallets());
        }
        vm.stopBroadcast();
    }
}

contract KintoMonitoringTest is AASetup,KYCSignature, UserOp {

    using ECDSAUpgradeable for bytes32;
    using SignatureChecker for address;

    KintoID _kintoID;
    EntryPoint _entryPoint;
    KintoWalletFactory _walletFactory;
    SponsorPaymaster _sponsorPaymaster;
    IKintoWallet _newWallet;

    function setUp() public {
        uint256 deployerPrivateKey = vm.envUint('PRIVATE_KEY');
        vm.startBroadcast(deployerPrivateKey);
        (_kintoID, _entryPoint, _walletFactory, _sponsorPaymaster) = _checkAccountAbstraction();
        vm.stopBroadcast();
    }

    function run() public {
        uint256 deployerPrivateKey = vm.envUint('PRIVATE_KEY');
        console.log('All AA setup is correct');
        vm.startBroadcast(deployerPrivateKey);
        address[] memory _addressesToMonitor = new address[](0);
        IKintoID.MonitorUpdateData[][] memory _traitsAndSanctions = new IKintoID.MonitorUpdateData[][](0);
        console.log('Update monitoring - no traits or sanctions update');
        _kintoID.monitor(_addressesToMonitor, _traitsAndSanctions);
        vm.stopBroadcast();
    }
}

contract KintoDeployTestCounter is AASetup,KYCSignature, UserOp {

    using ECDSAUpgradeable for bytes32;
    using SignatureChecker for address;

    KintoID _kintoID;
    EntryPoint _entryPoint;
    KintoWalletFactory _walletFactory;
    SponsorPaymaster _sponsorPaymaster;
    IKintoWallet _newWallet;

    function setUp() public {
        uint256 deployerPrivateKey = vm.envUint('PRIVATE_KEY');
        vm.startBroadcast(deployerPrivateKey);
        (_kintoID, _entryPoint, _walletFactory, _sponsorPaymaster) = _checkAccountAbstraction();
        vm.stopBroadcast();
    }

    function run() public {
        uint256 deployerPrivateKey = vm.envUint('PRIVATE_KEY');
        address deployerPublicKey = vm.envAddress('PUBLIC_KEY');
        console.log('All AA setup is correct');
        vm.startBroadcast(deployerPrivateKey);
        uint salt = 0;
        address newWallet = _walletFactory.getAddress(deployerPublicKey, deployerPublicKey, salt);
        if (!isContract(newWallet)) {
            console.log('ERROR: Wallet not deployed for owner', deployerPublicKey, 'at', newWallet);
            revert();
        }
        _newWallet = IKintoWallet(newWallet);
        // Counter contract
        address computed = _walletFactory.getContractAddress(
            bytes32(0), keccak256(abi.encodePacked(type(Counter).creationCode)));
        if (!isContract(computed)) {
            address created = _walletFactory.deployContract(0,
                abi.encodePacked(type(Counter).creationCode), bytes32(0));
            console.log('Deployed Counter contract at', created);
        } else {
            console.log('Counter already deployed at', computed);
        }
        Counter counter = Counter(computed);
        console.log('Before UserOp. Counter:', counter.count());
        // We add the deposit to the counter contract in the paymaster
        if (_sponsorPaymaster.balances(computed) <= 1e14) {
            _sponsorPaymaster.addDepositFor{value: 5e16}(computed);
            console.log('Adding paymaster balance to counter', computed);
        } else {
            console.log('Counter already has balance to pay for tx', computed);
        }
        // Let's send a transaction to the counter contract through our wallet
        uint startingNonce = _newWallet.getNonce();
        uint256[] memory privateKeys = new uint256[](1);
        privateKeys[0] = deployerPrivateKey;
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
        // Execute the transaction via the entry point
        _entryPoint.handleOps(userOps, payable(deployerPublicKey));
        console.log('After UserOp. Counter:', counter.count());
        vm.stopBroadcast();
    }
}

contract KintoDeployETHPriceIsRight is AASetup, KYCSignature, UserOp {

    using ECDSAUpgradeable for bytes32;
    using SignatureChecker for address;

    KintoID _kintoID;
    EntryPoint _entryPoint;
    KintoWalletFactory _walletFactory;
    SponsorPaymaster _sponsorPaymaster;
    IKintoWallet _newWallet;

    function setUp() public {
        uint256 deployerPrivateKey = vm.envUint('PRIVATE_KEY');
        vm.startBroadcast(deployerPrivateKey);
        (_kintoID, _entryPoint, _walletFactory, _sponsorPaymaster) = _checkAccountAbstraction();
        vm.stopBroadcast();
    }

    function run() public {
        uint256 deployerPrivateKey = vm.envUint('PRIVATE_KEY');
        address deployerPublicKey = vm.envAddress('PUBLIC_KEY');
        console.log('All AA setup is correct');
        vm.startBroadcast(deployerPrivateKey);
        uint salt = 0;
        address newWallet = _walletFactory.getAddress(deployerPublicKey, deployerPublicKey, salt);
        if (!isContract(newWallet)) {
            console.log('ERROR: Wallet not deployed for owner', deployerPublicKey, 'at', newWallet);
            revert();
        }
        _newWallet = IKintoWallet(newWallet);
        // Counter contract
        address computed = _walletFactory.getContractAddress(
            bytes32(0), keccak256(abi.encodePacked(type(ETHPriceIsRight).creationCode)));
        if (!isContract(computed)) {
            address created = _walletFactory.deployContract(0,
                abi.encodePacked(type(ETHPriceIsRight).creationCode), bytes32(0));
            console.log('Deployed ETHPriceIsRight contract at', created);
        } else {
            console.log('ETHPriceIsRight already deployed at', computed);
        }
        ETHPriceIsRight ethpriceisright = ETHPriceIsRight(computed);
        console.log('ETHPriceIsRight guess count', ethpriceisright.guessCount());
        console.log('ETHPriceIsRight avg guess', ethpriceisright.avgGuess());

        console.log('Balance paymaster', _sponsorPaymaster.balances(computed));
        // We add the deposit to the counter contract in the paymaster
        if (_sponsorPaymaster.balances(computed) <= 1e14) {
            _sponsorPaymaster.addDepositFor{value: 5e16}(computed);
            console.log('Adding paymaster balance to ETHPriceIsRight', computed);
            console.log('Balance paymaster', _sponsorPaymaster.balances(computed));
        } else {
            console.log('ETHPriceIsRight already has balance to pay for tx', computed);
        }
        // Let's send a transaction to the counter contract through our wallet
        uint startingNonce = _newWallet.getNonce();
        uint256[] memory privateKeys = new uint256[](1);
        privateKeys[0] = deployerPrivateKey;
        UserOperation memory userOp = this.createUserOperationWithPaymasterCustomGas(
            block.chainid,
            address(_newWallet),
            startingNonce,
            privateKeys,
            address(ethpriceisright),
            0,
            abi.encodeWithSignature('enterGuess(uint256)', 7000),
            address(_sponsorPaymaster),
            [uint256(5000000), 3, 3]
        );
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = userOp;
        // Execute the transaction via the entry point
        _entryPoint.handleOps(userOps, payable(deployerPublicKey));
        console.log('After UserOp. ETHPriceIsRight guess count', ethpriceisright.guessCount());
        console.log('After UserOp. ETHPriceIsRight avg guess', ethpriceisright.avgGuess());
        vm.stopBroadcast();
    }
}
