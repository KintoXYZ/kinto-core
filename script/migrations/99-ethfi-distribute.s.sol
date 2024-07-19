// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../../src/wallet/KintoWalletFactory.sol";
import "../../src/wallet/KintoWallet.sol";
import "../../src/sample/Counter.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import {ERC20Multisender} from "@kinto-core-script/utils/ERC20Multisender.sol";
import {stdJson} from "forge-std/StdJson.sol";

contract EthfiDistributeSignersScript is MigrationHelper {
    using stdJson for string;

    address internal constant ETHFI = 0xe70F10CD4bD932a28b80d48D771026a4c88E6285;

    function run() public override {
        super.run();

        vm.broadcast(deployerPrivateKey);
        ERC20Multisender sender = new ERC20Multisender{salt: 0}();
        saveContractAddress("ERC20Multisender", address(sender));

        _whitelistApp(address(sender));

        _handleOps(abi.encodeWithSelector(IERC20.approve.selector, address(sender), type(uint256).max), ETHFI);

        string memory json = vm.readFile("./script/data/weETH_final_distribution.json");
        string[] memory keys = vm.parseJsonKeys(json, "$");
        address[] memory users = new address[](keys.length);
        uint256[] memory amounts = new uint256[](keys.length);
        for (uint256 index = 0; index < keys.length; index++) {
            uint256 amount = json.readUint(string.concat(".", keys[index]));
            address user = vm.parseAddress(keys[index]);
            users[index] = user;
            amounts[index] = amount;
        }

        uint256 total = IERC20(ETHFI).balanceOf(kintoAdminWallet);

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
                batchAmounts[i - start] = amounts[i] * total / 1e18;
            }

            bytes memory selectorAndParams =
                abi.encodeWithSelector(ERC20Multisender.multisendToken.selector, ETHFI, batchUsers, batchAmounts);
            _handleOps(selectorAndParams, address(sender));
        }

        assertEq(IERC20(ETHFI).balanceOf(0x68242cfeDA40Ff286b045D388f4c5859713027AE), total * 313510000000000000 / 1e18);
        assertEq(IERC20(ETHFI).balanceOf(0x5A68fa975f400679b88F8b43c4a8A0580E7F9cd9), total * 10000000000000 / 1e18);
    }
}
