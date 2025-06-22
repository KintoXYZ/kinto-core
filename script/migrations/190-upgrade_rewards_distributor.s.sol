// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {RewardsDistributor} from "../../src/liquidity-mining/RewardsDistributor.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract UpgradeRD is MigrationHelper {
    function run() public override {
        super.run();
        bytes memory bytecode;
        address impl;

        RewardsDistributor distr = RewardsDistributor(_getChainDeployment("RewardsDistributor"));


        bytecode = abi.encodePacked(
            type(RewardsDistributor).creationCode,
            abi.encode(
                _getChainDeployment("KINTO"), distr.startTime(), distr.walletFactory()
            )
        );

        impl = _deployImplementationAndUpgrade("RewardsDistributor", "V13", bytecode);

        // Transfer 400,000 K to treasury
        _handleOps(abi.encodeWithSelector(RewardsDistributor.transferToTreasury.selector, 400_000 * 1e18), address(distr));
        assertGt(IERC20(_getChainDeployment("KINTO")).balanceOf(_getChainDeployment("Treasury")), 2_000_000 * 1e18);

        saveContractAddress("RewardsDistributorV13-impl", impl);
    }
}
