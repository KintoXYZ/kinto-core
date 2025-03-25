// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {SuperToken} from "@kinto-core/tokens/bridged/SuperToken.sol";

import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import {ArtifactsReader} from "@kinto-core-test/helpers/ArtifactsReader.sol";
import {UUPSProxy} from "@kinto-core-test/helpers/UUPSProxy.sol";

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "forge-std/Test.sol";

import {Constants} from "@kinto-core-script/migrations/mainnet/const.sol";

contract UpgradeScript is Constants, Test, MigrationHelper {
    SuperToken internal token;
    address internal newImpl;
    address internal kAddress;

    function setUp() public {}

    function run() public override {
        super.run();

        kAddress = _getChainDeployment("K", block.chainid);
        if (kAddress == address(0)) {
            console.log("Not deployed", kAddress);
            return;
        }

        // Deploy implementation
        vm.broadcast(deployerPrivateKey);
        newImpl = address(new SuperToken(18));
        // Stop broadcast because the Owner is Safe account

        token = SuperToken(payable(kAddress));
        vm.broadcast(deployerPrivateKey);
        token.upgradeToAndCall(newImpl, bytes(""));

        // Checks
        assertEq(token.decimals(), 18, "Invalid decimals");

        saveContractAddress("K-impl", newImpl);
    }
}
