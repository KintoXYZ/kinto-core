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

        uint256 amount_1 = 25e18;
        uint256 amount_2 = 1e18;

        address recipient_1 = 0x4F9F1c7b9fE78dD394e28CCEa16cb8D0465E61f1;
        address recipient_2 = 0xD8511CedBf108a50fDf429A08e55E49356890169;

        address kintoToken = _getChainDeployment("KINTO");
        uint256 balanceBefore_1 = ERC20(kintoToken).balanceOf(recipient_1);
        uint256 balanceBefore_2 = ERC20(kintoToken).balanceOf(recipient_2);

        // Burn tokens from RD
        _handleOps(
            abi.encodeWithSelector(
                BridgedToken.burn.selector, _getChainDeployment("RewardsDistributor"), amount_1 + amount_2
            ),
            kintoToken
        );

        // Mint tokens to winner address
        _handleOps(abi.encodeWithSelector(BridgedToken.mint.selector, recipient_1, amount_1), kintoToken);
        _handleOps(abi.encodeWithSelector(BridgedToken.mint.selector, recipient_2, amount_2), kintoToken);

        // Check that tokens received
        assertEq(ERC20(kintoToken).balanceOf(recipient_1) - balanceBefore_1, amount_1);
        assertEq(ERC20(kintoToken).balanceOf(recipient_2) - balanceBefore_2, amount_2);
    }
}
