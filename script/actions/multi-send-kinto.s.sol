// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {StrSlice, toSlice} from "@dk1a/solidity-stringutils/src/StrSlice.sol";

using {toSlice} for string;

import "@kinto-core-test/helpers/ArrayHelpers.sol";
import {BridgedKinto} from "@kinto-core/tokens/bridged/BridgedKinto.sol";
import {BridgedToken} from "@kinto-core/tokens/bridged/BridgedToken.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import {ERC20Multisender} from "@kinto-core-script/utils/ERC20MultiSender.sol";

import {stdJson} from "forge-std/StdJson.sol";
import "forge-std/Script.sol";
import "forge-std/console.sol";

contract MintBatchKintoScript is MigrationHelper {
    using Strings for *;
    using ArrayHelpers for *;

    address[] users;
    uint256[] amounts;
    uint256[] usersBalancesBefore;

    function run() public override {
        super.run();

        BridgedKinto kintoToken = BridgedKinto(_getChainDeployment("KINTO"));

        string memory userFile = vm.envString("USERS_FILE");
        uint256 totalAmount;

        while (true) {
            string memory addrAndAmountStr = vm.readLine(userFile);
            // if empty string then end of the file
            if (addrAndAmountStr.equal("")) {
                break;
            }
            (bool found, StrSlice addrStr, StrSlice amountStr) = addrAndAmountStr.toSlice().splitOnce(toSlice(","));
            if (!found) revert("Data file is broken.");

            address addr = vm.parseAddress(addrStr.toString());
            console2.log("addr:", addr);
            users.push(addr);

            uint256 amount = vm.parseUint(amountStr.toString()) * 1e18;
            // amounts are in 1e18
            console2.log("amount:", amount);
            amounts.push(amount);
            totalAmount += amount;

            usersBalancesBefore.push(kintoToken.balanceOf(addr));
        }

        console2.log("totalAmount:", totalAmount);

        uint256 totalSupplyBefore = kintoToken.totalSupply();
        // Burn tokens from RD
        _handleOps(
            abi.encodeWithSelector(BridgedToken.burn.selector, _getChainDeployment("RewardsDistributor"), totalAmount),
            address(kintoToken)
        );

        // Check that tokens are burnt
        assertEq(totalSupplyBefore - totalAmount, kintoToken.totalSupply());

        uint256[] memory privKeys = new uint256[](2);
        privKeys[0] = deployerPrivateKey;
        privKeys[1] = hardwareWalletType;

        uint256 batchSize = 100;
        uint256 totalBatches = (users.length + batchSize - 1) / batchSize;

        for (uint256 batchIndex = 0; batchIndex < totalBatches; batchIndex++) {
            uint256 start = batchIndex * batchSize;
            uint256 end = start + batchSize;
            if (end > users.length) {
                end = users.length;
            }

            address[] memory batchUsers = new address[](end - start);
            uint256[] memory batchAmounts = new uint256[](end - start);

            for (uint256 i = start; i < end; i++) {
                batchUsers[i - start] = users[i];
                batchAmounts[i - start] = amounts[i];
            }

            _handleOps(
                abi.encodeWithSelector(BridgedToken.batchMint.selector, batchUsers, batchAmounts), address(kintoToken)
            );
        }

        // Check that tokens are minted
        assertEq(totalSupplyBefore, kintoToken.totalSupply());

        for (uint256 index = 0; index < usersBalancesBefore.length; index++) {
            assertEq(usersBalancesBefore[index] + amounts[index], kintoToken.balanceOf(users[index]));
        }
    }
}
