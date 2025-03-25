// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {SuperToken} from "@kinto-core/tokens/bridged/SuperToken.sol";

import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import {Test} from "forge-std/Test.sol";
import "forge-std/Script.sol";
import "forge-std/console.sol";

contract BurnKintoTokenScript is Test, MigrationHelper {
    // Constants
    bytes32 constant CONTROLLER_ROLE = keccak256("CONTROLLER_ROLE");
    address public constant KINTO_TOKEN_ARBITRUM = 0x010700AB046Dd8e92b0e3587842080Df36364ed3;
    uint256 public constant TOKENS_TO_BURN = 36_350e18; // 36,350 KINTO tokens

    SuperToken internal token;

    function run() public override {
        super.run();

        // Make sure we're on Arbitrum
        require(block.chainid == ARBITRUM_CHAINID, "This script must be run on Arbitrum");

        token = SuperToken(payable(KINTO_TOKEN_ARBITRUM));

        console.log("Burning KINTO tokens on Arbitrum");
        console.log("Token address:", KINTO_TOKEN_ARBITRUM);
        console.log("Amount to burn:", TOKENS_TO_BURN);
        console.log("Burner (deployer):", deployer);

        // Grant controller role to deployer if needed
        if (!token.hasRole(CONTROLLER_ROLE, deployer)) {
            console.log("Granting CONTROLLER_ROLE to deployer");

            vm.broadcast(deployerPrivateKey);
            token.grantRole(CONTROLLER_ROLE, deployer);
        }

        // Get initial balances and total supply
        uint256 initialBalance = token.balanceOf(deployer);
        uint256 initialTotalSupply = token.totalSupply();
        console.log("Initial deployer balance:", initialBalance);
        console.log("Initial total supply:", initialTotalSupply);

        // Burn tokens from deployer
        vm.broadcast(deployerPrivateKey);
        token.burn(deployer, TOKENS_TO_BURN);

        // Get final balances
        uint256 finalBalance = token.balanceOf(deployer);
        uint256 finalTotalSupply = token.totalSupply();
        console.log("Final deployer balance:", finalBalance);
        console.log("Final total supply:", finalTotalSupply);

        // Verify the burn was successful
        assertEq(finalBalance, initialBalance - TOKENS_TO_BURN, "Balance should decrease by burned amount");
        assertEq(finalTotalSupply, initialTotalSupply - TOKENS_TO_BURN, "Total supply should decrease by burned amount");

        console.log("Successfully burned", TOKENS_TO_BURN, "KINTO tokens from", deployer);

        // Revoke controller role if it was granted in this script
        if (token.hasRole(CONTROLLER_ROLE, deployer)) {
            console.log("Revoking CONTROLLER_ROLE from deployer");

            vm.broadcast(deployerPrivateKey);
            token.revokeRole(CONTROLLER_ROLE, deployer);
        }
    }
}
