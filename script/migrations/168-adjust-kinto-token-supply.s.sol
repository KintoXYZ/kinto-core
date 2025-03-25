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
 * @title AdjustKintoTokenSupplyScript
 * @notice Script to adjust KINTO token supply to 10M with specific distribution:
 * - 2M to Treasury
 * - 4.5M to VestingContract
 * - The rest to RewardsDistributor
 */
contract AdjustKintoTokenSupplyScript is MigrationHelper {
    using LibString for *;
    using Strings for string;
    using stdJson for string;

    // Token address
    address public constant KINTO = 0x010700808D59d2bb92257fCafACfe8e5bFF7aB87;

    // Target total supply
    uint256 public constant TOTAL_SUPPLY = 10_000_000e18; // 10M tokens

    // Target allocation
    uint256 public constant TREASURY_ALLOCATION = 2_000_000e18; // 2M tokens
    uint256 public constant VESTING_ALLOCATION = 4_500_000e18; // 4.5M tokens

    function run() public override {
        super.run();

        // Get contract addresses
        address treasury = _getChainDeployment("Treasury");
        address vestingContract = _getChainDeployment("VestingContract");
        address rewardsDistributor = _getChainDeployment("RewardsDistributor");

        console2.log("Treasury: %s", treasury);
        console2.log("VestingContract: %s", vestingContract);
        console2.log("RewardsDistributor: %s", rewardsDistributor);

        // Get current balances and total supply
        uint256 treasuryBalance = IERC20(KINTO).balanceOf(treasury);
        uint256 vestingBalance = IERC20(KINTO).balanceOf(vestingContract);
        uint256 rewardsBalance = IERC20(KINTO).balanceOf(rewardsDistributor);
        uint256 currentSupply = IERC20(KINTO).totalSupply();

        console2.log("Current supply: %s", currentSupply / 1e18);
        console2.log("Current Treasury balance: %s", treasuryBalance / 1e18);
        console2.log("Current VestingContract balance: %s", vestingBalance / 1e18);
        console2.log("Current RewardsDistributor balance: %s", rewardsBalance / 1e18);

        uint256 mintAmount;

        // Now adjust Treasury balance
        if (treasuryBalance < TREASURY_ALLOCATION) {
            // Mint tokens to Treasury
            mintAmount = TREASURY_ALLOCATION - treasuryBalance;
            console2.log("Minting %s tokens to Treasury", mintAmount / 1e18);

            _handleOps(abi.encodeWithSelector(BridgedToken.mint.selector, treasury, mintAmount), KINTO);
        }

        // Adjust VestingContract balance
        if (vestingBalance < VESTING_ALLOCATION) {
            // Mint tokens to VestingContract
            mintAmount = VESTING_ALLOCATION - vestingBalance;
            console2.log("Minting %s tokens to VestingContract", mintAmount / 1e18);

            _handleOps(abi.encodeWithSelector(BridgedToken.mint.selector, vestingContract, mintAmount), KINTO);
        }

        // Update current supply and balances
        treasuryBalance = IERC20(KINTO).balanceOf(treasury);
        vestingBalance = IERC20(KINTO).balanceOf(vestingContract);
        currentSupply = IERC20(KINTO).totalSupply();

        // Calculate rewards allocation
        mintAmount = TOTAL_SUPPLY - currentSupply;
        console2.log("Minting %s tokens to RewardsDistributor", mintAmount / 1e18);

        // Mint tokens to RewardsDistributor
        _handleOps(abi.encodeWithSelector(BridgedToken.mint.selector, rewardsDistributor, mintAmount), KINTO);

        // Final verification
        treasuryBalance = IERC20(KINTO).balanceOf(treasury);
        vestingBalance = IERC20(KINTO).balanceOf(vestingContract);
        rewardsBalance = IERC20(KINTO).balanceOf(rewardsDistributor);
        currentSupply = IERC20(KINTO).totalSupply();

        console2.log("Final supply: %s", currentSupply / 1e18);
        console2.log("Final Treasury balance: %s", treasuryBalance / 1e18);
        console2.log("Final VestingContract balance: %s", vestingBalance / 1e18);
        console2.log("Final RewardsDistributor balance: %s", rewardsBalance / 1e18);

        // Verify target allocations
        assertEq(treasuryBalance, TREASURY_ALLOCATION, "Treasury allocation incorrect");
        assertEq(vestingBalance, VESTING_ALLOCATION, "VestingContract allocation incorrect");
        assertEq(currentSupply, TOTAL_SUPPLY, "Total supply incorrect");
    }
}
