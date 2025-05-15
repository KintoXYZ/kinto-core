// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {console2} from "forge-std/console2.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import {StakedKinto} from "@kinto-core/vaults/StakedKinto.sol";

contract StakeSeasonTwo is MigrationHelper {
    function run() public override {
        super.run();

        // vm.broadcast(deployerPrivateKey);

        StakedKinto stakedKinto = StakedKinto(payable(_getChainDeployment("StakedKinto")));
        if (address(stakedKinto) == address(0)) {
            console2.log("StakedKinto has to be deployed");
            return;
        }

        bytes memory bytecode = abi.encodePacked(type(StakedKinto).creationCode);

        _deployImplementationAndUpgrade("StakedKinto", "V3", bytecode);
        (uint256 startTime, uint256 endTime, uint256 rewardRate, uint256 maxCapacity, address rewardToken) =
            stakedKinto.getPeriodInfo(0);
        // Checks interface change
        console2.log("rewardToken", rewardToken);
        require(rewardToken == address(0), "Wrong address 2");
        // Starts new period

        _handleOps(
            abi.encodeWithSelector(
                StakedKinto.startNewPeriod.selector,
                1755236567, // Aug 15th
                1,
                500_000 * 1e18,
                0x010700808D59d2bb92257fCafACfe8e5bFF7aB87
            ),
            payable(_getChainDeployment("StakedKinto"))
        );

        (startTime, endTime, rewardRate, maxCapacity, rewardToken) = stakedKinto.getPeriodInfo(1);
        require(endTime == 1755236567, "Wrong end time");
        require(rewardRate == 1, "Wrong reward rate");
        require(maxCapacity == 500_000 * 1e18, "Wrong max capacity");
        require(rewardToken == 0x010700808D59d2bb92257fCafACfe8e5bFF7aB87, "Wrong address");
    }
}
