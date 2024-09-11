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

        uint256 amount = 50e18;
        address devWinner = 0xcdc3ad2a02764c3a9E9ff49B2daB19f65F07B7Bc;

        address kintoToken = _getChainDeployment("KINTO");
        uint256 balanceBefore = ERC20(kintoToken).balanceOf(devWinner);

        // Burn tokens from RD
        _handleOps(
            abi.encodeWithSelector(BridgedToken.burn.selector, _getChainDeployment("RewardsDistributor"), amount),
            kintoToken
        );

        // Mint tokens to investor address
        _handleOps(abi.encodeWithSelector(BridgedToken.mint.selector, devWinner, amount), kintoToken);

        // Check that tokens received
        assertEq(ERC20(kintoToken).balanceOf(devWinner) - balanceBefore, amount);
    }
}
