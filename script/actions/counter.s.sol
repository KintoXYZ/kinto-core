// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {SimpleAccount} from "@aa/samples/SimpleAccount.sol";
import {EntryPoint} from "@aa/core/EntryPoint.sol";
import {PackedUserOperation} from "@aa/interfaces/PackedUserOperation.sol";

import {Counter} from "../../src/sample/Counter.sol";
import {IKintoWallet} from "../../src/interfaces/IKintoWallet.sol";
import {IKintoWalletFactory} from "../../src/interfaces/IKintoWalletFactory.sol";
import {SponsorPaymaster} from "../../src/paymasters/SponsorPaymaster.sol";

import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";

import "forge-std/console.sol";
import "forge-std/Script.sol";

/// @notice This script executes a user operation that calls the `increment()` function using your smart account.
contract KintoCounterScript is MigrationHelper {
    EntryPoint _entryPoint;

    function setUp() public {}

    function run() public override {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerPublicKey = vm.addr(deployerPrivateKey);
        console.log("Deployer is", vm.addr(deployerPrivateKey));

        Counter counter = Counter(_getChainDeployment("Counter"));
        console.log("Before UserOp. Counter:", counter.count());

        SimpleAccount account = SimpleAccount(payable(0xd1DA7E60F0f4480031C58986272EA8127E1073A9));
        console2.log('account:', address(account));

        // send a tx to the counter contract through our wallet
        uint256 nonce = account.getNonce();
        uint256[] memory privateKeys = new uint256[](1);
        privateKeys[0] = deployerPrivateKey;

        PackedUserOperation[] memory userOps = new PackedUserOperation[](1);

        // increment counter
        userOps[0] = _createUserOperation(
            block.chainid,
            address(account),
            address(counter),
            0,
            nonce,
            privateKeys,
            abi.encodeWithSignature("increment()"),
            address(0)
        );

        vm.broadcast(deployerPrivateKey);
        EntryPoint(payable(_getChainDeployment("EntryPoint"))).handleOps(userOps, payable(vm.addr(privateKeys[0])));

        console.log("After UserOp. Counter:", counter.count());
    }
}
