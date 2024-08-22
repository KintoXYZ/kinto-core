// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {LibString} from "solady/utils/LibString.sol";
import {ERC20} from "@openzeppelin-5.0.1/contracts/token/ERC20/ERC20.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {BridgedToken} from "@kinto-core/tokens/bridged/BridgedToken.sol";
import {BridgedKinto} from "@kinto-core/tokens/bridged/BridgedKinto.sol";
import {IKintoWallet} from "@kinto-core/interfaces/IKintoWallet.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import {UUPSProxy} from "@kinto-core-test/helpers/UUPSProxy.sol";
import {console2} from "forge-std/console2.sol";

contract TransferDclmScript is MigrationHelper {
    using LibString for *;
    using Strings for string;
    using stdJson for string;

    function run() public override {
        super.run();

        uint256 amount = 5_000e18;
        address investor = 0x85bD43dBb99A2290E4cD930fc6B952D903f83fFb;

        address kintoToken = _getChainDeployment("KINTO");
        uint256 balanceBefore = ERC20(kintoToken).balanceOf(investor);

        // Burn tokens from RD
        _handleOps(
            abi.encodeWithSelector(BridgedToken.burn.selector, _getChainDeployment("RewardsDistributor"), amount),
            kintoToken
        );

        // Mint tokens to investor address
        _handleOps(abi.encodeWithSelector(BridgedToken.mint.selector, investor, amount), kintoToken);

        // Check that tokens received
        assertEq(ERC20(kintoToken).balanceOf(investor) - balanceBefore, amount);
    }
}
