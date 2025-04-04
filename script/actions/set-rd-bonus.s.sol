// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import {IKintoWallet} from "@kinto-core/interfaces/IKintoWallet.sol";
import {RewardsDistributor} from "@kinto-core/liquidity-mining/RewardsDistributor.sol";

import {stdJson} from "forge-std/StdJson.sol";
import "forge-std/Script.sol";
import "forge-std/console.sol";

contract UpdateRootScript is MigrationHelper {
    using stdJson for string;

    function run() public override {
        super.run();

        uint256 bonusAmount = 100_000 * 1e18;

        _handleOps(
            abi.encodeWithSelector(RewardsDistributor.updateBonusAmount.selector, bonusAmount),
            _getChainDeployment("RewardsDistributor")
        );
    }
}
