// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../../src/wallet/KintoWalletFactory.sol";
import "../../src/wallet/KintoWallet.sol";
import {StakedKinto} from "@kinto-core/vaults/StakedKinto.sol";
import {BridgedKinto} from "@kinto-core/tokens/bridged/BridgedKinto.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import {ERC20Multisender} from "@kinto-core-script/utils/ERC20MultiSender.sol";
import {stdJson} from "forge-std/StdJson.sol";

import "forge-std/console2.sol";

contract StakedKintoDistributeScript is MigrationHelper {
    using stdJson for string;

    function run() public override {
        super.run();

        // Load JSON file with precomputed allocations
        string memory json = vm.readFile("./script/data/staked_kinto_distribution.json");
        string[] memory keys = vm.parseJsonKeys(json, "$");

        // Prepare arrays for users and amounts
        address[] memory users = new address[](keys.length);
        uint256[] memory amounts = new uint256[](keys.length);
        uint256 totalAmount = 0;

        // Parse JSON data
        for (uint256 index = 0; index < keys.length; index++) {
            uint256 amount = json.readUint(string.concat(".", keys[index]));
            address user = vm.parseAddress(keys[index]);
            users[index] = user;
            amounts[index] = amount;
            totalAmount += amount;
        }

        console2.log("Total Users:", keys.length);
        console2.log("Total StakedKinto to distribute:", totalAmount);

        // Check that we're distributing approximately the expected amount
        require(totalAmount <= 64100 * 1e18, "Total exceeds 64,100 sK");

        // Get the address of the StakedKinto token
        address stakedKintoAddress = _getChainDeployment("StakedKinto");
        require(stakedKintoAddress != address(0), "StakedKinto not deployed");

        _handleOps(
            abi.encodeWithSelector(
                IERC20.approve.selector, address(_getChainDeployment("StakedKinto")), type(uint256).max
            ),
            address(_getChainDeployment("KINTO"))
        );

        _handleOps(
            abi.encodeWithSelector(
                StakedKinto.deposit.selector,
                BridgedKinto(_getChainDeployment("KINTO")).balanceOf(kintoAdminWallet),
                kintoAdminWallet
            ),
            stakedKintoAddress
        );

        uint256 initialBalance = IERC20(stakedKintoAddress).balanceOf(kintoAdminWallet);

        // Store initial balances of some key users for verification
        uint256[] memory initialBalances = new uint256[](5);
        if (keys.length >= 5) {
            for (uint256 i = 0; i < 5; i++) {
                initialBalances[i] = IERC20(stakedKintoAddress).balanceOf(users[i]);
            }
        }

        // First, approve StakedKinto token for the multisender contract
        bytes memory selectorAndParams = abi.encodeWithSelector(
            IERC20.approve.selector, address(_getChainDeployment("ERC20Multisender")), type(uint256).max
        );
        _handleOps(selectorAndParams, stakedKintoAddress);

        // Process in batches to avoid hitting gas limits
        uint256 batchSize = 300;
        uint256 totalBatches = (keys.length + batchSize - 1) / batchSize;

        for (uint256 batchIndex = 0; batchIndex < totalBatches; batchIndex++) {
            uint256 start = batchIndex * batchSize;
            uint256 end = start + batchSize;
            if (end > keys.length) {
                end = keys.length;
            }

            address[] memory batchUsers = new address[](end - start);
            uint256[] memory batchAmounts = new uint256[](end - start);

            for (uint256 i = start; i < end; i++) {
                batchUsers[i - start] = users[i];
                batchAmounts[i - start] = amounts[i];
            }

            // Use multisendToken to distribute the tokens
            selectorAndParams = abi.encodeWithSelector(
                ERC20Multisender.multisendToken.selector, stakedKintoAddress, batchUsers, batchAmounts
            );
            _handleOps(selectorAndParams, _getChainDeployment("ERC20Multisender"));

            console2.log("Processed batch", batchIndex + 1, "of", totalBatches);
        }

        // Verify final balances of some key users
        if (keys.length >= 5) {
            for (uint256 i = 0; i < 5; i++) {
                uint256 finalBalance = IERC20(stakedKintoAddress).balanceOf(users[i]);
                uint256 expectedIncrease = amounts[i];

                console2.log("User", users[i]);
                console2.log("Initial:", initialBalances[i]);
                console2.log("Final:", finalBalance);
                assertEq(finalBalance - initialBalances[i], expectedIncrease, "Incorrect transfer amount");
            }
        }

        assertEq(IERC20(stakedKintoAddress).balanceOf(kintoAdminWallet), initialBalance - totalAmount, "Some tokens left");

        console2.log("StakedKinto distribution completed successfully!");
    }
}
