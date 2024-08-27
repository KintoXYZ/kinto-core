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
        address[10] memory winners = [
            //Gakusha
            0x3e1DE1d04a4Ccf9F8E229c2103D7C753AF2f51C1,
            0x5e2DA0f4b5fFf884EAF7b1f430DE7c9d0D6cE1e3,
            0x69f9E439A16B90EC36A2C27Bc7D130bBFcac96B4,
            0x8076BD3B7b78638a40D2fFa9376551707BbA27Cb,
            0xb0543cf8dEa187913ab21b3568323F3Fe43c6C24,
            0xC42f37a8b36f6C4AE7f214989357A4fEcEb55Ea9,
            0xd7F966447d912c785420340ebabE8dFFDBe3A856,
            0x4De408C181c0E8C59a99f6C6940006Fa6c93B299,
            0xef74A5C1F9288D141F0c924889aC295f3e798a49,
            0x94b2fdCDa6847cC026faCcad83bF4603ba1daF7F
        ];

        address kintoToken = _getChainDeployment("KINTO");

        uint256[] memory balanceBefore = new uint256[](winners.length);
        for (uint256 i = 0; i < winners.length; i++) {
            balanceBefore[i] = ERC20(kintoToken).balanceOf(winners[i]);
        }

        // Burn tokens from RD
        _handleOps(
            abi.encodeWithSelector(
                BridgedToken.burn.selector, _getChainDeployment("RewardsDistributor"), amount * winners.length
            ),
            kintoToken
        );

        // Mint tokens to investor address
        for (uint256 i = 0; i < winners.length; i++) {
            _handleOps(abi.encodeWithSelector(BridgedToken.mint.selector, winners[i], amount), kintoToken);
        }

        // Check that tokens received
        for (uint256 i = 0; i < winners.length; i++) {
            assertEq(ERC20(kintoToken).balanceOf(winners[i]) - balanceBefore[i], amount);
        }
    }
}
