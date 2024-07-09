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
            type(RewardsDistributor).creationCode,
            abi.encode(_getChainDeployment("KINTO"), _getChainDeployment("EngenCredits"), LIQUIDITY_MINING_START_DATE)
        );

        // replaceOwner(IKintoWallet(kintoAdminWallet), 0x4632F4120DC68F225e7d24d973Ee57478389e9Fd);
        // hardwareWalletType = 1;

        //address impl = _deployImplementationAndUpgrade("RewardsDistributor", "V3", bytecode, keccak256("V3"));

        RewardsDistributor distr = RewardsDistributor(_getChainDeployment("RewardsDistributor"));

        _upgradeTo(address(distr), 0x86FCC650cE6FfA75ee1dfF98d943e4d1ff16c4fB, deployerPrivateKey);

        assertEq(address(distr.KINTO()), 0x010700808D59d2bb92257fCafACfe8e5bFF7aB87);
        assertEq(address(distr.ENGEN()), 0xD1295F0d8789c3E0931A04F91049dB33549E9C8F);
        assertEq(distr.startTime(), LIQUIDITY_MINING_START_DATE);

        saveContractAddress("RewardsDistributorV3-impl", 0x86FCC650cE6FfA75ee1dfF98d943e4d1ff16c4fB);
    }
}
