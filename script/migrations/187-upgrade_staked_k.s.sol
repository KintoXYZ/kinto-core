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
        require(rewardToken == 0x05DC0010C9902EcF6CBc921c6A4bd971c69E5A2E, "Wrong address");
        // Starts new period
        uint256[] memory privateKeys = new uint256[](1);
        privateKeys[0] = deployerPrivateKey;
        _handleOps(
            abi.encodeWithSelector(
                StakedKinto.startNewPeriod.selector,
                1755236567, // Aug 15th
                1,
                500_000 * 1e18,
                0x010700808D59d2bb92257fCafACfe8e5bFF7aB87
            ),
            payable(kintoAdminWallet),
            _getChainDeployment("StakedKinto"),
            0,
            address(0),
            privateKeys
        );
        (startTime, endTime, rewardRate, maxCapacity, rewardToken) = stakedKinto.getPeriodInfo(1);
        require(endTime == 1755236567, "Wrong end time");
        require(rewardRate == 1, "Wrong reward rate");
        require(maxCapacity == 500_000 * 1e18, "Wrong max capacity");
        require(rewardToken == 0x05DC0010C9902EcF6CBc921c6A4bd971c69E5A2E, "Wrong address");
    }
}
