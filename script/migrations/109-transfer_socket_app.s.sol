// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../../src/wallet/KintoWallet.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import {KintoAppRegistry} from "@kinto-core/apps/KintoAppRegistry.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract KintoMigration97DeployScript is MigrationHelper {
    function run() public override {
        super.run();

        KintoAppRegistry kintoAppRegistry = KintoAppRegistry(payable(_getChainDeployment("KintoAppRegistry")));

        address socketWallet = 0x219E29cFa9422b6bC47aE4855d3194d5eFb9a396;
        uint256 appId = 6;

        _handleOps(
            abi.encodeWithSelector(
                bytes4(keccak256("safeTransferFrom(address,address,uint256)")), kintoAdminWallet, socketWallet, appId
            ),
            address(_getChainDeployment("KintoAppRegistry"))
        );

        assertEq(kintoAppRegistry.ownerOf(appId), socketWallet);
    }
}
