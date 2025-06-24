// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {console2} from "forge-std/console2.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import {StakedKinto} from "@kinto-core/vaults/StakedKinto.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract StakeSeasonTwo is MigrationHelper {
    function run() public override {
        super.run();

        // vm.broadcast(deployerPrivateKey);

        StakedKinto stakedKinto = StakedKinto(payable(_getChainDeployment("StakedKinto")));
        // IERC20 kinto = IERC20(_getChainDeployment("KINTO"));
        if (address(stakedKinto) == address(0)) {
            console2.log("StakedKinto has to be deployed");
            return;
        }

        bytes memory bytecode = abi.encodePacked(type(StakedKinto).creationCode);

        // _deployImplementationAndUpgrade("StakedKinto", "V5", bytecode);
        // console2.log("balanceOf", stakedKinto.owner());
        // uint balanceAccBefore = stakedKinto.balanceOf(0xf9e2E3F36C45F31ef4579c481C040772f086577b);
        // require(stakedKinto.balanceOf(0x26E508D5d63499e549D958B42c4e2630272Ce2a2) > 0, "Wrong balance");
        // _handleOps(
        //     abi.encodeWithSelector(
        //         StakedKinto.confiscateStake.selector
        //     ),
        //     payable(_getChainDeployment("StakedKinto"))
        // );
        // require(stakedKinto.balanceOf(0x26E508D5d63499e549D958B42c4e2630272Ce2a2) == 0, "Wrong balance");
        // require(stakedKinto.balanceOf(0xf9e2E3F36C45F31ef4579c481C040772f086577b) == balanceAccBefore, "Wrong balance");
        // require(kinto.balanceOf(0xf9e2E3F36C45F31ef4579c481C040772f086577b) > 39000 * 1e18, "Wrong balance");
        _deployImplementationAndUpgrade("StakedKinto", "V8", bytecode);
    }
}
