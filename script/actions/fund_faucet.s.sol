// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@kinto-core/wallet/KintoWalletFactory.sol";
import "@kinto-core/wallet/KintoWallet.sol";
import "@kinto-core/paymasters/SponsorPaymaster.sol";

import "@kinto-core-test/helpers/Create2Helper.sol";
import "@kinto-core-test/helpers/ArtifactsReader.sol";
import "@kinto-core-test/helpers/UUPSProxy.sol";

import "forge-std/Script.sol";
import "forge-std/console.sol";

contract FundFaucetScript is Create2Helper, ArtifactsReader {
    function setUp() public {}

    // NOTE: this migration must be run from the ledger admin
    function run() public {
        console.log("RUNNING ON CHAIN WITH ID", vm.toString(block.chainid));
        // Execute this script with the ledger admin but first we use the hot wallet
        console.log("Executing with address", msg.sender, vm.envAddress("LEDGER_ADMIN"));
        address factoryAddr = _getChainDeployment("KintoWalletFactory");
        if (factoryAddr == address(0)) {
            console.log("Need to execute main deploy script first", factoryAddr);
            return;
        }
        // Start admin
        vm.startBroadcast();
        uint256 AMOUNT_TO_SEND = 0.1 ether;
        KintoWalletFactory(address(factoryAddr)).sendMoneyToAccount{value: AMOUNT_TO_SEND}(
            0xb539019776eF803E89EC062Ad54cA24D1Fdb008a
        );
        vm.stopBroadcast();
        require(address(0xb539019776eF803E89EC062Ad54cA24D1Fdb008a).balance >= AMOUNT_TO_SEND, "amount was not sent");
        // writes the addresses to a file
        console.log("Faucet amount sent");
    }
}
