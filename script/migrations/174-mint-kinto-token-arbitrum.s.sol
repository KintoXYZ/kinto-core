// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {SuperToken} from "@kinto-core/tokens/bridged/SuperToken.sol";

import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import {Test} from "forge-std/Test.sol";
import "forge-std/Script.sol";
import "forge-std/console.sol";

contract MintKintoTokenScript is Test, MigrationHelper {
    // Constants
    bytes32 constant CONTROLLER_ROLE = keccak256("CONTROLLER_ROLE");
    address public constant KINTO_TOKEN_ARBITRUM = 0x010700AB046Dd8e92b0e3587842080Df36364ed3;
    uint256 public constant TOKENS_TO_MINT = 36_350e18; // 36,350 KINTO tokens

    SuperToken internal token;

    function run() public override {
        super.run();

        // Make sure we're on Arbitrum
        require(block.chainid == ARBITRUM_CHAINID, "This script must be run on Arbitrum");

        token = SuperToken(payable(KINTO_TOKEN_ARBITRUM));

        console.log("Minting KINTO tokens on Arbitrum");
        console.log("Token address:", KINTO_TOKEN_ARBITRUM);
        console.log("Amount to mint:", TOKENS_TO_MINT);
        console.log("Recipient (deployer):", deployer);

        // Grant controller role to deployer if needed
        if (!token.hasRole(CONTROLLER_ROLE, deployer)) {
            console.log("Granting CONTROLLER_ROLE to deployer");

            vm.broadcast(deployerPrivateKey);
            token.grantRole(CONTROLLER_ROLE, deployer);
        }

        // Mint tokens to deployer
        vm.broadcast(deployerPrivateKey);
        token.mint(deployer, TOKENS_TO_MINT);

        console.log("Successfully minted", TOKENS_TO_MINT, "KINTO tokens to", deployer);

        // Verify the tokens were minted
        uint256 balance = token.balanceOf(deployer);
        console.log("New deployer balance:", balance);

        // Revoke controller role if it was granted in this script
        if (token.hasRole(CONTROLLER_ROLE, deployer)) {
            console.log("Revoking CONTROLLER_ROLE from deployer");

            vm.broadcast(deployerPrivateKey);
            token.revokeRole(CONTROLLER_ROLE, deployer);
        }
    }
}
