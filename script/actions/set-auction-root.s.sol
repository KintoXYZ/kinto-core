// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import {IKintoWallet} from "@kinto-core/interfaces/IKintoWallet.sol";
import {SealedBidTokenSale} from "@kinto-core/apps/SealedBidTokenSale.sol";

import {stdJson} from "forge-std/StdJson.sol";
import "forge-std/Script.sol";
import "forge-std/console.sol";

contract UpdateRootScript is MigrationHelper {
    using stdJson for string;

    function run() public override {
        super.run();

        bytes32 newRoot = vm.envBytes32("ROOT");

        _handleOps(
            abi.encodeWithSelector(SealedBidTokenSale.setMerkleRoot.selector, newRoot),
            _getChainDeployment("SealedBidTokenSale"),
            deployerPrivateKey
        );
    }
}
