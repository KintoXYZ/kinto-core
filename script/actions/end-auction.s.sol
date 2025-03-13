// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import {IKintoWallet} from "@kinto-core/interfaces/IKintoWallet.sol";
import {SealedBidTokenSale} from "@kinto-core/apps/SealedBidTokenSale.sol";

import {stdJson} from "forge-std/StdJson.sol";
import "forge-std/console.sol";

contract Script is MigrationHelper {
    using stdJson for string;

    function run() public override {
        super.run();

        _handleOps(
            abi.encodeWithSelector(SealedBidTokenSale.endSale.selector),
            _getChainDeployment("SealedBidTokenSale"),
            deployerPrivateKey
        );
    }
}
