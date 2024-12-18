// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@kinto-core/tokens/EngenBadges.sol";
import "../../test/helpers/ArtifactsReader.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";

contract KintoMigration54DeployScript is MigrationHelper {
    function run() public override {
        super.run();

        //is it already deployed?
        address engenBadgesAddr = _getChainDeployment("EngenBadges");
        if (engenBadgesAddr != address(0)) {
            console.log("EngenBadges already deployed", engenBadgesAddr);
            return;
        }

        bytes memory bytecode =
            abi.encodePacked(type(EngenBadges).creationCode, abi.encode(_getChainDeployment("KintoWalletFactory")));
        address implementation = _deployImplementation("EngenBadges", "V1", bytecode);
        address proxy = _deployProxy("EngenBadges", implementation);

        _fundPaymaster(proxy, deployerPrivateKey);
        _whitelistApp(proxy);

        //UserOp initialize with parameters
        _handleOps(
            abi.encodeWithSelector(EngenBadges.initialize.selector, "https://kinto.xyz/api/v1/get-badge-nft/{id}"),
            address(proxy),
            deployerPrivateKey
        );

        uint256[] memory ids = new uint256[](11);
        ids[0] = 1;
        ids[1] = 2;
        ids[2] = 3;
        ids[3] = 4;
        ids[4] = 5;
        ids[5] = 6;
        ids[6] = 7;
        ids[7] = 8;
        ids[8] = 9;
        ids[9] = 10;
        ids[10] = 11;

        _handleOps(
            abi.encodeWithSelector(EngenBadges.mintBadges.selector, _getChainDeployment("KintoWallet-admin"), ids),
            address(proxy),
            deployerPrivateKey
        );
    }
}
