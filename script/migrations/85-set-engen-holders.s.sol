// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {IKintoWallet} from "@kinto-core/interfaces/IKintoWallet.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import {RewardsDistributor} from "@kinto-core/liquidity-mining/RewardsDistributor.sol";
import {stdJson} from "forge-std/StdJson.sol";

import "forge-std/console2.sol";

contract SetEngenHoldersScript is MigrationHelper {
    using stdJson for string;

    function run() public override {
        super.run();

        RewardsDistributor distr = RewardsDistributor(_getChainDeployment("RewardsDistributor"));

        replaceOwner(IKintoWallet(kintoAdminWallet), 0x4632F4120DC68F225e7d24d973Ee57478389e9Fd);
        hardwareWalletType = 1;

        // string memory json = vm.readFile("./script/data/engen-holders.json");
        // address[] memory users = json.readAddressArray("$");

        uint256 batchSize = 100;
        uint256 totalBatches = (users.length + batchSize - 1) / batchSize;

        for (uint256 batchIndex = 0; batchIndex < totalBatches; batchIndex++) {
            uint256 start = batchIndex * batchSize;
            uint256 end = start + batchSize;
            if (end > users.length) {
                end = users.length;
            }

            address[] memory batchUsers = new address[](end - start);
            bool[] memory batchValues = new bool[](end - start);

            for (uint256 i = start; i < end; i++) {
                batchUsers[i - start] = users[i];
                batchValues[i - start] = true;
            }

            _handleOps(
                abi.encodeWithSelector(RewardsDistributor.updateEngenHolders.selector, batchUsers, batchValues),
                address(distr)
            );
        }

        assertEq(distr.engenHolders(0x4f2204D3c9965F031f9147B0558D01D6b56ce442), true);
        assertEq(distr.engenHolders(0xB7dacf22A631Bbaa23B1a700062540987F3A8799), true);
        assertEq(distr.engenHolders(0x45511Fce841b6D4Ee3c8F97355a4c37f0412E24c), true);
    }
}
