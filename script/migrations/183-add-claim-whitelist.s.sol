// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {console2} from "forge-std/console2.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import {RewardsDistributor} from "@kinto-core/liquidity-mining/RewardsDistributor.sol";

contract AddClaimWhitelistScript is MigrationHelper {
    function run() public override {
        super.run();

        // Target wallet to be added to the claim whitelist
        address walletToWhitelist = 0x7D467D99028199D99B1c91850C4dea0c82aDDF52;

        // Address of the RewardsDistributor contract
        address rewardsDistributor = _getChainDeployment("RewardsDistributor");

        // Add the wallet to the claim whitelist using _handleOps
        _handleOps(abi.encodeWithSignature("addToClaimWhitelist(address)", walletToWhitelist), rewardsDistributor);

        // Verify the wallet was added to the whitelist
        assertTrue(RewardsDistributor(rewardsDistributor).isClaimWhitelisted(walletToWhitelist));

        console2.log("Wallet 0x7D467D99028199D99B1c91850C4dea0c82aDDF52 successfully added to claim whitelist");
    }
}
