// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {console2} from "forge-std/console2.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import {StakedKinto} from "@kinto-core/vaults/StakedKinto.sol";

contract StakeSeasonThree is MigrationHelper {
    function run() public override {
        super.run();

        // vm.broadcast(deployerPrivateKey);

        StakedKinto stakedKinto = StakedKinto(payable(_getChainDeployment("StakedKinto")));
        if (address(stakedKinto) == address(0)) {
            console2.log("StakedKinto has to be deployed");
            return;
        }

        bytes memory bytecode = abi.encodePacked(type(StakedKinto).creationCode);

        _deployImplementationAndUpgrade("StakedKinto", "V14", bytecode);
        (uint256 startTime, uint256 endTime, uint256 rewardRate, uint256 maxCapacity, address rewardToken) =
            stakedKinto.getPeriodInfo(0);

        // Starts new period

        _handleOps(
            abi.encodeWithSelector(
                StakedKinto.startNewPeriod.selector,
                1764547200, // Nov 30th
                1,
                500_000 * 1e18,
                0x010700808D59d2bb92257fCafACfe8e5bFF7aB87
            ),
            payable(_getChainDeployment("StakedKinto"))
        );

        (startTime, endTime, rewardRate, maxCapacity, rewardToken) = stakedKinto.getPeriodInfo(2);
        require(endTime == 1764547200, "Wrong end time");
        require(rewardRate == 1, "Wrong reward rate");
        require(maxCapacity == 500_000 * 1e18, "Wrong max capacity");
        require(rewardToken == 0x010700808D59d2bb92257fCafACfe8e5bFF7aB87, "Wrong address");

        // Check calculate rewards
        uint256 rewards = stakedKinto.calculateRewards(address(0xe68dAF0de5152e155CFfE2B2d116b74E6CA5CcB3), 1);
        require(rewards >= 170 * 1e18 && rewards <= 172 * 1e18, "Wrong rewards");
    }
}
