// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {LibString} from "solady/utils/LibString.sol";
import {IERC20} from "@openzeppelin-5.0.1/contracts/interfaces/IERC20.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import {console2} from "forge-std/console2.sol";
import {BridgedToken} from "@kinto-core/tokens/bridged/BridgedToken.sol";

/**
 * @title MintKintoToAdminScript
 * @notice Script to mint 36,350 KINTO tokens to the Target address and burn the same amount from RewardsDistributor
 * to maintain the same total supply.
 */
contract MintKintoToAdminScript is MigrationHelper {
    using LibString for *;
    using Strings for string;
    using stdJson for string;

    // Address to send tokens to
    address public constant TARGET = 0x567F86E6ca46dFc0CC024B6ddAb1CB66807C1653;

    // Token address
    address public constant KINTO = 0x010700808D59d2bb92257fCafACfe8e5bFF7aB87;

    // Amount to mint and burn
    uint256 public constant AMOUNT = 200_000e18;

    function run() public override {
        super.run();

        // Get RewardsDistributor address
        address rewardsDistributor = _getChainDeployment("RewardsDistributor");
        console2.log("RewardsDistributor: %s", rewardsDistributor);

        // Log current balances and total supply
        uint256 targetBalance = IERC20(KINTO).balanceOf(TARGET);
        uint256 rewardsBalance = IERC20(KINTO).balanceOf(rewardsDistributor);
        uint256 currentSupply = IERC20(KINTO).totalSupply();

        console2.log("Target address: %s", TARGET);
        console2.log("Current supply: %s", currentSupply / 1e18);
        console2.log("Current Target balance: %s", targetBalance / 1e18);
        console2.log("Current RewardsDistributor balance: %s", rewardsBalance / 1e18);
        console2.log("Amount to transfer: %s", AMOUNT / 1e18);

        // Check if RewardsDistributor has enough balance
        require(rewardsBalance >= AMOUNT, "RewardsDistributor doesn't have enough balance");

        // Burn tokens from RewardsDistributor first
        console2.log("Burning %s tokens from RewardsDistributor", AMOUNT / 1e18);
        _handleOps(abi.encodeWithSelector(BridgedToken.burn.selector, rewardsDistributor, AMOUNT), KINTO);

        // Mint tokens to Target
        console2.log("Minting %s tokens to Target", AMOUNT / 1e18);
        _handleOps(abi.encodeWithSelector(BridgedToken.mint.selector, TARGET, AMOUNT), KINTO);

        // Verify the operations
        uint256 newAdminBalance = IERC20(KINTO).balanceOf(TARGET);
        uint256 newRewardsBalance = IERC20(KINTO).balanceOf(rewardsDistributor);
        uint256 newSupply = IERC20(KINTO).totalSupply();

        console2.log("Final supply: %s", newSupply / 1e18);
        console2.log("Final Target balance: %s", newAdminBalance / 1e18);
        console2.log("Final RewardsDistributor balance: %s", newRewardsBalance / 1e18);

        // Verify balances
        assertEq(newAdminBalance, targetBalance + AMOUNT, "Target balance incorrect");
        assertEq(newRewardsBalance, rewardsBalance - AMOUNT, "RewardsDistributor balance incorrect");
        assertEq(newSupply, currentSupply, "Total supply should remain unchanged");
    }
}
