// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import {IKintoWallet} from "@kinto-core/interfaces/IKintoWallet.sol";
import {RewardsDistributor} from "@kinto-core/liquidity-mining/RewardsDistributor.sol";

import {stdJson} from "forge-std/StdJson.sol";
import "forge-std/Script.sol";
import "forge-std/console.sol";

contract ClaimKintoScript is MigrationHelper {
    using stdJson for string;

    function run() public override {
        super.run();

        bytes32[] memory proof = vm.envOr("PROOF", ",", new bytes32[](0));
        address user = vm.envAddress("USER");
        uint256 amount = vm.envUint("AMOUNT");

        _handleOps(
            abi.encodeWithSelector(RewardsDistributor.claim.selector, proof, user, amount),
            _getChainDeployment("RewardsDistributor")
        );
    }
}
