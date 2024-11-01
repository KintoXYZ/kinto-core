// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {IKintoWallet} from "@kinto-core/interfaces/IKintoWallet.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import {RewardsDistributor} from "@kinto-core/liquidity-mining/RewardsDistributor.sol";

contract UpgradeDistributorScript is MigrationHelper {
    function run() public override {
        super.run();

        uint256 LIQUIDITY_MINING_START_DATE = 1718690400; // June 18th 2024

        bytes memory bytecode = abi.encodePacked(
            type(RewardsDistributor).creationCode,
            abi.encode(
                _getChainDeployment("KINTO"), LIQUIDITY_MINING_START_DATE, _getChainDeployment("KintoWalletFactory")
            )
        );

        address impl = _deployImplementationAndUpgrade("RewardsDistributor", "V7", bytecode);

        RewardsDistributor distr = RewardsDistributor(_getChainDeployment("RewardsDistributor"));

        assertEq(address(distr.KINTO()), 0x010700808D59d2bb92257fCafACfe8e5bFF7aB87);
        assertEq(distr.startTime(), LIQUIDITY_MINING_START_DATE);
        assertEq(distr.walletFactory(), _getChainDeployment("KintoWalletFactory"));

        saveContractAddress("RewardsDistributorV7-impl", impl);
    }
}
