// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {console2} from "forge-std/console2.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import {StakedKinto} from "@kinto-core/vaults/StakedKinto.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract ExtendSeasonTwoTime is MigrationHelper {
    struct Record {
        address user;
        uint256 shares;
        bool mint;
    }

    Record[] public records;

    function run() public override {
        super.run();

        // vm.broadcast(deployerPrivateKey);

        StakedKinto stakedKinto = StakedKinto(payable(_getChainDeployment("StakedKinto")));
        if (address(stakedKinto) == address(0)) {
            console2.log("StakedKinto has to be deployed");
            return;
        }

        bytes memory bytecode = abi.encodePacked(type(StakedKinto).creationCode);

        _deployImplementationAndUpgrade("StakedKinto", "V13", bytecode);

        _handleOps(
            abi.encodeWithSelector(StakedKinto.setEndTime.selector, 1756677600),
            payable(_getChainDeployment("StakedKinto"))
        );

        (, uint256 endTime,,,) = stakedKinto.getPeriodInfo(1);
        require(endTime == 1756677600, "Wrong end time");
    }
}
