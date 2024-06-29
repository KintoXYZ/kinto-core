// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {LibString} from "solady/utils/LibString.sol";
import {ERC20} from "@openzeppelin-5.0.1/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin-5.0.1/contracts/interfaces/IERC20.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {IAccessControl} from "@openzeppelin-5.0.1/contracts/access/IAccessControl.sol";
import {IKintoWallet} from "@kinto-core/interfaces/IKintoWallet.sol";
import {RewardsDistributor} from "@kinto-core/liquidity-mining/RewardsDistributor.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import {console2} from "forge-std/console2.sol";

contract SetUpdateRoleDistributorScript is MigrationHelper {
    using LibString for *;
    using Strings for string;
    using stdJson for string;

    function run() public override {
        super.run();

        RewardsDistributor rewardsDistributor = RewardsDistributor(0xD157904639E89df05e89e0DabeEC99aE3d74F9AA);
        address relayer = 0x0ED31428E4bCb3cdf8A1fCD4656Ee965f4241711;

        // replaceOwner(IKintoWallet(kintoAdminWallet), 0x4632F4120DC68F225e7d24d973Ee57478389e9Fd);
        // hardwareWalletType = 1;

        _whitelistApp(address(rewardsDistributor));

        _handleOps(
            abi.encodeWithSelector(IAccessControl.grantRole.selector, rewardsDistributor.UPDATER_ROLE(), relayer),
            address(rewardsDistributor)
        );

        assertTrue(rewardsDistributor.hasRole(rewardsDistributor.UPDATER_ROLE(), relayer));

        console2.log("All checks passed!");
    }
}
