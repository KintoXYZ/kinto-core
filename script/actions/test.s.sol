// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@aa/core/EntryPoint.sol";

import "@kinto-core/KintoID.sol";
import "@kinto-core/interfaces/IKintoID.sol";
import "@kinto-core/sample/Counter.sol";
import "@kinto-core/sample/ETHPriceIsRight.sol";
import "@kinto-core/interfaces/IKintoWallet.sol";
import "@kinto-core/wallet/KintoWalletFactory.sol";
import "@kinto-core/paymasters/SponsorPaymaster.sol";

import "@kinto-core-script/utils/MigrationHelper.sol";

import "forge-std/console.sol";
import "forge-std/Script.sol";

// This script is used to test the wallet creation
contract KintoDeployTestWalletScript is MigrationHelper {
    IKintoWallet _newWallet;

    function setUp() public {}

    function run() public override {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        uint256 recipientKey = vm.envUint("TEST_PRIVATE_KEY");
        address recipientWallet = vm.rememberKey(recipientKey);
        console.log("Deployer is", vm.addr(deployerPrivateKey));
        console.log("Recipient wallet is", recipientWallet);

        uint256 totalWalletsCreated = factory.totalWallets();
        console.log("Recipient wallet is KYC'd:", kintoID.isKYC(recipientWallet));
        if (!kintoID.isKYC(recipientWallet)) {
            IKintoID.SignatureData memory sigdata =
                _auxCreateSignature(kintoID, recipientWallet, recipientKey, block.timestamp + 50000);
            uint16[] memory traits = new uint16[](0);
            // NOTE: must be called from KYC_PROVIDER_ROLE
            console.log("Sender has KYC_PROVIDER_ROLE:", kintoID.hasRole(kintoID.KYC_PROVIDER_ROLE(), msg.sender));
            vm.broadcast(deployerPrivateKey);
            kintoID.mintIndividualKyc(sigdata, traits);
        }
        console.log("This factory has", totalWalletsCreated, "created");

        bytes32 salt = 0;
        address newWallet = factory.getAddress(recipientWallet, recipientWallet, salt);
        if (isContract(newWallet)) {
            console.log("Wallet already deployed for owner", recipientWallet, "at", newWallet);
        } else {
            vm.broadcast(deployerPrivateKey);
            IKintoWallet ikw = factory.createAccount(recipientWallet, recipientWallet, salt);
            console.log("Created wallet", address(ikw));
            console.log("Total Wallets:", factory.totalWallets());
        }
    }
}

// This script is used to test the monitor function of the KintoID
contract KintoMonitoringTest is MigrationHelper {
    using SignatureChecker for address;

    IKintoWallet _newWallet;

    function setUp() public {}

    function run() public override {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        console.log("Deployer is", vm.addr(deployerPrivateKey));

        address[] memory _addressesToMonitor = new address[](0);
        IKintoID.MonitorUpdateData[][] memory _traitsAndSanctions = new IKintoID.MonitorUpdateData[][](0);
        console.log("Update monitoring - no traits or sanctions update");

        // NOTE: must be called from KYC_PROVIDER_ROLE
        console.log("Sender has KYC_PROVIDER_ROLE:", kintoID.hasRole(kintoID.KYC_PROVIDER_ROLE(), msg.sender));
        vm.broadcast(deployerPrivateKey);
        kintoID.monitor(_addressesToMonitor, _traitsAndSanctions);
    }
}

// This script is used to test the deployment of a contract through the factory and further interaction with it
contract KintoDeployTestCounter is MigrationHelper {
    using SignatureChecker for address;

    IKintoWallet _newWallet;

    function setUp() public {}

    function run() public override {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerPublicKey = vm.addr(deployerPrivateKey);
        console.log("Deployer is", vm.addr(deployerPrivateKey));

        address newWallet = factory.getAddress(deployerPublicKey, deployerPublicKey, bytes32(0));
        if (!isContract(newWallet)) {
            console.log("No wallet found with owner", deployerPublicKey, "at", newWallet);
            vm.broadcast(deployerPrivateKey);
            IKintoWallet ikw = factory.createAccount(deployerPublicKey, deployerPublicKey, 0);
            console.log("- A new wallet has been created", address(ikw));
        }
        _newWallet = IKintoWallet(newWallet);

        // Counter contract
        address computed =
            factory.getContractAddress(bytes32(0), keccak256(abi.encodePacked(type(Counter).creationCode)));
        if (!isContract(computed)) {
            vm.broadcast(deployerPrivateKey);
            address created =
                factory.deployContract(deployerPublicKey, 0, abi.encodePacked(type(Counter).creationCode), bytes32(0));
            console.log("Counter contract deployed at", created);
        } else {
            console.log("Counter already deployed at", computed);
        }

        // deposit ETH to the counter contract in the paymaster
        if (paymaster.balances(computed) <= 1e14) {
            vm.broadcast(deployerPrivateKey);
            paymaster.addDepositFor{value: 5e16}(computed);
            console.log("Added paymaster balance to counter", computed);
        } else {
            console.log("Counter already has balance to pay for tx", computed);
        }

        // deposit ETH to the wallet contract in the paymaster
        if (paymaster.balances(address(_newWallet)) <= 1e14) {
            vm.broadcast(deployerPrivateKey);
            paymaster.addDepositFor{value: 5e16}(address(_newWallet));
            console.log("Added paymaster balance to wallet", address(_newWallet));
        } else {
            console.log("Wallet already has balance to pay for tx", address(_newWallet));
        }

        Counter counter = Counter(computed);
        console.log("Before UserOp. Counter:", counter.count());

        // send a tx to the counter contract through our wallet
        uint256 nonce = _newWallet.getNonce();
        uint256[] memory privateKeys = new uint256[](1);
        privateKeys[0] = deployerPrivateKey;

        UserOperation[] memory userOps = new UserOperation[](2);

        // whitelist counter contract in the wallet
        address[] memory targets = new address[](1);
        targets[0] = address(counter);

        bool[] memory flags = new bool[](1);
        flags[0] = true;

        userOps[0] = _createUserOperation(
            block.chainid,
            address(_newWallet),
            address(_newWallet),
            0,
            nonce,
            privateKeys,
            abi.encodeWithSignature("whitelistApp(address[],bool[])", targets, flags),
            address(paymaster)
        );

        // increment counter
        userOps[1] = _createUserOperation(
            block.chainid,
            address(_newWallet),
            address(counter),
            0,
            nonce + 1,
            privateKeys,
            abi.encodeWithSignature("increment()"),
            address(paymaster)
        );

        vm.broadcast(deployerPrivateKey);
        entryPoint.handleOps(userOps, payable(deployerPublicKey));

        console.log("After UserOp. Counter:", counter.count());
    }
}

// This script is used to test the deployment of a contract through the factory and further interaction with it
contract KintoDeployETHPriceIsRight is MigrationHelper {
    using SignatureChecker for address;

    IKintoWallet _newWallet;

    function setUp() public {}

    function run() public override {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerPublicKey = vm.addr(deployerPrivateKey);
        console.log("Deployer is", vm.addr(deployerPrivateKey));

        address newWallet = factory.getAddress(deployerPublicKey, deployerPublicKey, bytes32(0));
        if (!isContract(newWallet)) {
            console.log("No wallet found with owner", deployerPublicKey, "at", newWallet);
            vm.broadcast(deployerPrivateKey);
            IKintoWallet ikw = factory.createAccount(deployerPublicKey, deployerPublicKey, 0);
            console.log("- A new wallet has been created", address(ikw));
        }
        _newWallet = IKintoWallet(newWallet);

        // Counter contract
        address computed =
            factory.getContractAddress(bytes32(0), keccak256(abi.encodePacked(type(ETHPriceIsRight).creationCode)));
        if (!isContract(computed)) {
            vm.broadcast(deployerPrivateKey);
            address created = factory.deployContract(
                deployerPublicKey, 0, abi.encodePacked(type(ETHPriceIsRight).creationCode), bytes32(0)
            );
            console.log("ETHPriceIsRight contract deployed at", created);
        } else {
            console.log("ETHPriceIsRight already deployed at", computed);
        }

        ETHPriceIsRight ethpriceisright = ETHPriceIsRight(computed);
        console.log("ETHPriceIsRight guess count", ethpriceisright.guessCount());
        console.log("ETHPriceIsRight avg guess", ethpriceisright.avgGuess());

        // deposit ETH to the ETHPriceIsRight contract in the paymaster
        if (paymaster.balances(computed) <= 1e14) {
            vm.broadcast(deployerPrivateKey);
            paymaster.addDepositFor{value: 5e16}(computed);
            console.log("Added paymaster balance to ETHPriceIsRight", computed);
        } else {
            console.log("ETHPriceIsRight already has balance to pay for tx", computed);
        }

        // deposit ETH to the wallet contract in the paymaster
        if (paymaster.balances(address(_newWallet)) <= 1e14) {
            vm.broadcast(deployerPrivateKey);
            paymaster.addDepositFor{value: 5e16}(address(_newWallet));
            console.log("Added paymaster balance to wallet", address(_newWallet));
        } else {
            console.log("Wallet already has balance to pay for tx", address(_newWallet));
        }

        // send a tx to the ETHPriceIsRight contract through our wallet
        uint256 nonce = _newWallet.getNonce();
        uint256[] memory privateKeys = new uint256[](1);
        privateKeys[0] = deployerPrivateKey;
        UserOperation[] memory userOps = new UserOperation[](2);

        // whitelist ETHPriceIsRight contract in the wallet
        address[] memory targets = new address[](1);
        targets[0] = address(ethpriceisright);

        bool[] memory flags = new bool[](1);
        flags[0] = true;

        userOps[0] = _createUserOperation(
            block.chainid,
            address(_newWallet),
            address(_newWallet),
            0,
            nonce,
            privateKeys,
            abi.encodeWithSignature("whitelistApp(address[],bool[])", targets, flags),
            address(paymaster)
        );

        userOps[1] = _createUserOperation(
            block.chainid,
            address(_newWallet),
            address(ethpriceisright),
            0,
            nonce + 1,
            privateKeys,
            abi.encodeWithSignature("enterGuess(uint256)", 7000),
            address(paymaster)
        );

        vm.broadcast(deployerPublicKey);
        entryPoint.handleOps(userOps, payable(deployerPublicKey));

        console.log("After UserOp. ETHPriceIsRight guess count", ethpriceisright.guessCount());
        console.log("After UserOp. ETHPriceIsRight avg guess", ethpriceisright.avgGuess());
    }
}

// This script is used to test the deployment of a contract through the factory and further interaction with it
contract SendHanldeOps is MigrationHelper {
    using SignatureChecker for address;

    IKintoWallet _newWallet;

    function setUp() public {}

    function run() public override {
        KintoWallet kintoWallet = KintoWallet(payable(vm.envAddress("TEST_KINTO_WALLET")));
        bytes memory bytesOp = vm.envBytes("TEST_BYTESOP");
        if (bytesOp.length == 0) {
            console.log("No bytesOp provided");
            return;
        }

        uint256 deployerPrivateKey = vm.envUint("TEST_PRIVATE_KEY");
        address deployerPublicKey = vm.addr(deployerPrivateKey);
        console.log("Deployer is", vm.addr(deployerPrivateKey));

        // deposit ETH to the wallet contract in the paymaster
        if (paymaster.balances(address(kintoWallet)) <= 1e14) {
            vm.broadcast(deployerPrivateKey);
            paymaster.addDepositFor{value: 5e16}(address(kintoWallet));
            console.log("Added paymaster balance to wallet", address(kintoWallet));
        } else {
            console.log("Wallet already has balance to pay for tx", address(kintoWallet));
        }

        // send a tx to the counter contract through our wallet
        uint256 nonce = kintoWallet.getNonce();
        uint256[] memory privateKeys = new uint256[](1);
        privateKeys[0] = deployerPrivateKey;

        UserOperation[] memory userOps = new UserOperation[](1);

        userOps[0] = _createUserOperation(
            block.chainid,
            address(kintoWallet),
            address(kintoWallet),
            0,
            nonce,
            privateKeys,
            bytesOp,
            address(paymaster)
        );

        vm.broadcast(deployerPrivateKey);
        entryPoint.handleOps(userOps, payable(deployerPublicKey));
    }
}
