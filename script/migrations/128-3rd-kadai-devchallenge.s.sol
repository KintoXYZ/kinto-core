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

        uint256 kadai_amount = 50e18;
        uint256 devchallenge_amount = 100e18;

        address kadai_winner = 0x830Bbb9A0373D17113483f3C6bC5278A8D39D740;
        address devchallenge_winner = 0xa8c7477B0b4011c3BfFC944433642b309416166b;

        address kintoToken = _getChainDeployment("KINTO");
        uint256 kadai_balanceBefore = ERC20(kintoToken).balanceOf(kadai_winner);
        uint256 devchallenge_balanceBefore = ERC20(kintoToken).balanceOf(devchallenge_winner);

        // Burn tokens from RD
        _handleOps(
            abi.encodeWithSelector(
                BridgedToken.burn.selector,
                _getChainDeployment("RewardsDistributor"),
                kadai_amount + devchallenge_amount
            ),
            kintoToken
        );

        // Mint tokens to winner address
        _handleOps(abi.encodeWithSelector(BridgedToken.mint.selector, kadai_winner, kadai_amount), kintoToken);
        _handleOps(
            abi.encodeWithSelector(BridgedToken.mint.selector, devchallenge_winner, devchallenge_amount), kintoToken
        );

        // Check that tokens received
        assertEq(ERC20(kintoToken).balanceOf(kadai_winner) - kadai_balanceBefore, kadai_amount);
        assertEq(ERC20(kintoToken).balanceOf(devchallenge_winner) - devchallenge_balanceBefore, devchallenge_amount);
    }
}
