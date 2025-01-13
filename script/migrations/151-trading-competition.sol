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

        uint256[] memory kadai_amounts = new uint256[](7);
        kadai_amounts[0] = 50e18;
        kadai_amounts[1] = 20e18;
        kadai_amounts[2] = 10e18;
        kadai_amounts[3] = 50e18;
        kadai_amounts[4] = 20e18;
        kadai_amounts[5] = 10e18;
        kadai_amounts[6] = 50e18;

        address[] memory kadai_winners = new address[](7);
        kadai_winners[0] = 0xa13D24d265EFbd84c993e525A210458CE15081b9;
        kadai_winners[1] = 0x04bF0Fe175E23e3E4474712040f8EEBbf0484100;
        kadai_winners[2] = 0x956642E471D5DA741b34aBB14d1B74b46583cD80;

        kadai_winners[3] = 0x2025b0E5A1666c690E35f4638Fcfc319f03c8075;
        kadai_winners[4] = 0xa13D24d265EFbd84c993e525A210458CE15081b9;
        kadai_winners[5] = 0xCa42442258b9E9994Ec9EDe50b70bf1b3bAA491E;

        kadai_winners[6] = 0x71F51C64110709880260610EA8C411A28c067739;

        address kintoToken = _getChainDeployment("KINTO");
        uint256[] memory kadai_balancesBefore = new uint256[](7);
        for (uint256 i = 0; i < kadai_winners.length; i++) {
            kadai_balancesBefore[i] = ERC20(kintoToken).balanceOf(kadai_winners[i]);
        }

        // Burn tokens from RD
        uint256 totalAmount = 0;
        for (uint256 i = 0; i < kadai_amounts.length; i++) {
            totalAmount += kadai_amounts[i];
        }
        _handleOps(
            abi.encodeWithSelector(
                BridgedToken.burn.selector,
                _getChainDeployment("RewardsDistributor"),
                totalAmount
            ),
            kintoToken
        );

        // Mint tokens to winner address
        for (uint256 i = 0; i < kadai_winners.length; i++) {
            _handleOps(abi.encodeWithSelector(BridgedToken.mint.selector, kadai_winners[i], kadai_amounts[i]), kintoToken);
        }
    }
}
