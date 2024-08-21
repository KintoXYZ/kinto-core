// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {IKintoWallet} from "@kinto-core/interfaces/IKintoWallet.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import {RewardsDistributor} from "@kinto-core/liquidity-mining/RewardsDistributor.sol";

contract UpgradeDistributorScript is MigrationHelper {
    function run() public override {
        super.run();

        uint256 LIQUIDITY_MINING_START_DATE = 1718690400; // June 18th 2024

        abi.encodePacked(
            type(RewardsDistributor).creationCode, abi.encode(_getChainDeployment("KINTO"), LIQUIDITY_MINING_START_DATE)
        );

        RewardsDistributor distr = RewardsDistributor(_getChainDeployment("RewardsDistributor"));

        _upgradeTo(address(distr), 0x86FCC650cE6FfA75ee1dfF98d943e4d1ff16c4fB, deployerPrivateKey);

        assertEq(address(distr.KINTO()), 0x010700808D59d2bb92257fCafACfe8e5bFF7aB87);
        assertEq(distr.startTime(), LIQUIDITY_MINING_START_DATE);

        saveContractAddress("RewardsDistributorV3-impl", 0x86FCC650cE6FfA75ee1dfF98d943e4d1ff16c4fB);
    }
}
