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

        uint256 amount = 85_000e18;

        address mm_address = 0x26E508D5d63499e549D958B42c4e2630272Ce2a2;
        address rd_address = _getChainDeployment("RewardsDistributor");

        address kintoToken = _getChainDeployment("KINTO");
        uint256 mm_balanceBefore = ERC20(kintoToken).balanceOf(mm_address);
        uint256 rd_balanceBefore = ERC20(kintoToken).balanceOf(rd_address);

        // Burn tokens from mm_address
        _handleOps(abi.encodeWithSelector(BridgedToken.burn.selector, mm_address, amount), kintoToken);

        // Mint tokens to rd_address
        _handleOps(abi.encodeWithSelector(BridgedToken.mint.selector, rd_address, amount), kintoToken);

        uint256 mm_balanceAfter = ERC20(kintoToken).balanceOf(mm_address);
        uint256 rd_balanceAfter = ERC20(kintoToken).balanceOf(rd_address);

        // Check that tokens received
        assertEq(rd_balanceAfter, rd_balanceBefore + amount);
        assertEq(mm_balanceAfter, mm_balanceBefore - amount);
    }
}
