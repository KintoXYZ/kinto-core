// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {stdJson} from "forge-std/StdJson.sol";

import "../../src/wallet/KintoWallet.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import "@kinto-core/bridger/BridgerL2.sol";

contract AssignWstEthRefundsScript is MigrationHelper {
    using stdJson for string;

    function run() public override {
        super.run();

        BridgerL2 bridgerL2 = BridgerL2(_getChainDeployment("BridgerL2"));

        string memory json = vm.readFile("./script/data/wstETHgasUsed.json");
        string[] memory keys = vm.parseJsonKeys(json, "$");
        address[] memory users = new address[](keys.length);
        uint256[] memory amounts = new uint256[](keys.length);
        for (uint256 index = 0; index < keys.length; index++) {
            uint256 amount = json.readUint(string.concat(".", keys[index]));
            address user = vm.parseAddress(keys[index]);
            users[index] = user;
            amounts[index] = amount;
        }

        uint256 batchSize = 100;
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

            bytes memory selectorAndParams =
                abi.encodeWithSelector(BridgerL2.assignWstEthRefunds.selector, batchUsers, batchAmounts);
            _handleOps(selectorAndParams, address(bridgerL2), deployerPrivateKey);
        }
    }
}
