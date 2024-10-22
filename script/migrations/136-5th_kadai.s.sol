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

        uint256 kadai_amount_1 = 50e18;
        uint256 kadai_amount_2 = 51e18;
        uint256 kadai_amount_3 = 51e18;

        address kadai_winner_1 = 0xbb14fb6F2a2b8DB4AA924d561e4b7CBd7AB464fE;
        address kadai_winner_2 = 0x50F8d3bd8b3E02254BA2E092eb0d73f4ccaed4bD;
        address kadai_winner_3 = 0x39f8F1d7b4aC6087eE65445355cfbc95Da62cb54;

        address kintoToken = _getChainDeployment("KINTO");
        uint256 kadai_balanceBefore_1 = ERC20(kintoToken).balanceOf(kadai_winner_1);
        uint256 kadai_balanceBefore_2 = ERC20(kintoToken).balanceOf(kadai_winner_2);
        uint256 kadai_balanceBefore_3 = ERC20(kintoToken).balanceOf(kadai_winner_3);

        // Burn tokens from RD
        _handleOps(
            abi.encodeWithSelector(
                BridgedToken.burn.selector,
                _getChainDeployment("RewardsDistributor"),
                kadai_amount_1 + kadai_amount_2 + kadai_amount_3
            ),
            kintoToken
        );

        // Mint tokens to winner address
        _handleOps(abi.encodeWithSelector(BridgedToken.mint.selector, kadai_winner_1, kadai_amount_1), kintoToken);
        _handleOps(abi.encodeWithSelector(BridgedToken.mint.selector, kadai_winner_2, kadai_amount_2), kintoToken);
        _handleOps(abi.encodeWithSelector(BridgedToken.mint.selector, kadai_winner_3, kadai_amount_3), kintoToken);

        // Check that tokens received
        assertEq(ERC20(kintoToken).balanceOf(kadai_winner_1) - kadai_balanceBefore_1, kadai_amount_1);
        assertEq(ERC20(kintoToken).balanceOf(kadai_winner_2) - kadai_balanceBefore_2, kadai_amount_2);
        assertEq(ERC20(kintoToken).balanceOf(kadai_winner_3) - kadai_balanceBefore_3, kadai_amount_3);
    }
}
