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

contract Script is MigrationHelper {
    using LibString for *;
    using Strings for string;
    using stdJson for string;

    function run() public override {
        super.run();

        uint256 amount = 50_000e18;
        address shoku = 0x68242cfeDA40Ff286b045D388f4c5859713027AE;

        address kintoToken = _getChainDeployment("KINTO");

        // Burn tokens from RD
        _handleOps(
            abi.encodeWithSelector(BridgedToken.burn.selector, _getChainDeployment("RewardsDistributor"), amount),
            kintoToken
        );

        // Mint tokens to shoku address
        _handleOps(abi.encodeWithSelector(BridgedToken.mint.selector, shoku, amount), kintoToken);
    }
}
