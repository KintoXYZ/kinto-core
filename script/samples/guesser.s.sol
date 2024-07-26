// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@aa/core/EntryPoint.sol";

import "../../src/sample/ETHPriceIsRight.sol";
import "../../src/interfaces/IKintoWallet.sol";
import "../../src/paymasters/SponsorPaymaster.sol";
import "@kinto-core-script/utils/MigrationHelper.sol";

import "forge-std/console.sol";
import "forge-std/Script.sol";

/// @notice This script deploys an `ETHPriceIsRight` contract (skips deployment if already exists) and executes a user operation that calls the `enterGuess()` function using your smart account.
contract KintoGuesserScript is MigrationHelper {
    EntryPoint _entryPoint;
    SponsorPaymaster _sponsorPaymaster;
    IKintoWallet _newWallet;
    KintoWalletFactory _walletFactory;

    function setUp() public {}

    function run() public override {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerPublicKey = vm.addr(deployerPrivateKey);
        console.log("Deployer is", vm.addr(deployerPrivateKey));

        address newWallet = _walletFactory.getAddress(deployerPublicKey, deployerPublicKey, bytes32(0));
        if (!isContract(newWallet)) {
            console.log("No wallet found with owner", deployerPublicKey, "at", newWallet);
            vm.broadcast(deployerPrivateKey);
            address ikw = address(_walletFactory.createAccount(deployerPublicKey, deployerPublicKey, 0));
            console.log("- A new wallet has been created", ikw);
        }
        _newWallet = IKintoWallet(newWallet);

        // ETHPriceIsRight contract
        address computed = computeAddress(bytes32(0), abi.encodePacked(type(ETHPriceIsRight).creationCode));
        if (!isContract(computed)) {
            vm.broadcast(deployerPrivateKey);
            ETHPriceIsRight created = new ETHPriceIsRight{salt: bytes32(0)}();
            created.transferOwnership(deployerPublicKey);
            console.log("ETHPriceIsRight contract deployed at", address(created));
        } else {
            console.log("ETHPriceIsRight already deployed at", computed);
        }

        ETHPriceIsRight ethpriceisright = ETHPriceIsRight(computed);
        console.log("ETHPriceIsRight guess count", ethpriceisright.guessCount());
        console.log("ETHPriceIsRight avg guess", ethpriceisright.avgGuess());

        // deposit ETH to the ETHPriceIsRight contract in the paymaster
        if (_sponsorPaymaster.balances(computed) <= 1e14) {
            vm.broadcast(deployerPrivateKey);
            _sponsorPaymaster.addDepositFor{value: 5e16}(computed);
            console.log("Added paymaster balance to ETHPriceIsRight", computed);
        } else {
            console.log("ETHPriceIsRight already has balance to pay for tx", computed);
        }

        // deposit ETH to the wallet contract in the paymaster
        if (_sponsorPaymaster.balances(address(_newWallet)) <= 1e14) {
            vm.broadcast(deployerPrivateKey);
            _sponsorPaymaster.addDepositFor{value: 5e16}(address(_newWallet));
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
            address(_sponsorPaymaster)
        );

        userOps[1] = _createUserOperation(
            block.chainid,
            address(_newWallet),
            address(ethpriceisright),
            0,
            nonce + 1,
            privateKeys,
            abi.encodeWithSignature("enterGuess(uint256)", 7000),
            address(_sponsorPaymaster)
        );

        vm.broadcast(deployerPublicKey);
        _entryPoint.handleOps(userOps, payable(deployerPublicKey));

        console.log("After UserOp. ETHPriceIsRight guess count", ethpriceisright.guessCount());
        console.log("After UserOp. ETHPriceIsRight avg guess", ethpriceisright.avgGuess());
    }
}
