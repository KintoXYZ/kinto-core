// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {LibString} from "solady/utils/LibString.sol";
import {ERC20} from "@openzeppelin-5.0.1/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin-5.0.1/contracts/interfaces/IERC20.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {IKintoWallet} from "@kinto-core/interfaces/IKintoWallet.sol";
import {IKintoHook} from "@kinto-core/socket/IKintoHook.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import {UUPSProxy} from "@kinto-core-test/helpers/UUPSProxy.sol";
import {console2} from "forge-std/console2.sol";

contract UpdateKintoHookScript is MigrationHelper {
    using LibString for *;
    using Strings for string;
    using stdJson for string;

    function run() public override {
        super.run();

        address kintoHook = 0x2bF336782456649bb38dBF9aEe1021E7244694a4;
        address miningAdaptor = 0xa5e9f2dd08582bBe2D41FAd465Cf8feCbFcbF6F3;
        address rewardsDistributor = 0xD157904639E89df05e89e0DabeEC99aE3d74F9AA;

        // replaceOwner(IKintoWallet(kintoAdminWallet), 0x4632F4120DC68F225e7d24d973Ee57478389e9Fd);
        // hardwareWalletType = 1;

        _whitelistApp(kintoHook);

        _handleOps(abi.encodeWithSelector(IKintoHook.setReceiver.selector, rewardsDistributor, true), kintoHook);
        _handleOps(abi.encodeWithSelector(IKintoHook.setSender.selector, miningAdaptor, true), kintoHook);

        assertEq(IKintoHook(kintoHook).receiveAllowlist(rewardsDistributor), true);
        assertEq(IKintoHook(kintoHook).senderAllowlist(miningAdaptor), true);

        console2.log("All checks passed!");
    }
}
