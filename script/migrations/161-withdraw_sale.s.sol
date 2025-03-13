// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {SealedBidTokenSale} from "@kinto-core/apps/SealedBidTokenSale.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import {UUPSProxy} from "@kinto-core-test/helpers/UUPSProxy.sol";
import {UUPSUpgradeable} from "@openzeppelin-5.0.1/contracts/proxy/utils/UUPSUpgradeable.sol";
import "forge-std/console2.sol";

contract Script is MigrationHelper {
    function run() public override {
        super.run();

        address proxy = _getChainDeployment("SealedBidTokenSale");

        uint256[] memory privateKeys = new uint256[](1);
        privateKeys[0] = deployerPrivateKey;
        _handleOps(
            abi.encodeWithSelector(SealedBidTokenSale.withdrawProceeds.selector, 3_840_000 * 1e6),
            payable(kintoAdminWallet),
            address(proxy),
            0,
            address(0),
            privateKeys
        );
    }
}
