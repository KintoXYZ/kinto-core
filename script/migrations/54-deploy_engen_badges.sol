// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@kinto-core/tokens/EngenBadges.sol";
import "@kinto-core/interfaces/IEngenBadges.sol";
import "../../test/helpers/ArtifactsReader.sol";
import "./utils/MigrationHelper.sol";

contract KintoMigration54DeployScript is MigrationHelper {
    using ECDSAUpgradeable for bytes32;

    function run() public override {
        super.run();

        //is it already deployed?
        address engenBadgesAddr = _getChainDeployment("EngenBadges");
        if (engenBadgesAddr != address(0)) {
            console.log("EngenBadges already deployed", engenBadgesAddr);
            return;
        }
        
        bytes memory bytecode = abi.encodePacked(type(EngenBadges).creationCode, abi.encode(_getChainDeployment("KintoWalletFactory")));
        address implementation = _deployImplementation("EngenBadges", "V1", bytecode);
        address proxy = _deployProxy("EngenBadges", implementation);

        _fundPaymaster(proxy, deployerPrivateKey);
        _whitelistApp(proxy, deployerPrivateKey);

        //UserOp initialize with parameters
        _handleOps(
            abi.encodeWithSelector(
                IEngenBadges.initialize.selector, 
                "http://kinto.xyz/api/v1/get-badge-nft/"
            ),
            address(proxy),
            deployerPrivateKey
        );

        //Remove comment to mint sample badges for the KintoWallet-admin

        /*
        uint256[] memory ids = new uint256[](2);
        ids[0] = 0;
        ids[1] = 3;
        
        _handleOps(
            abi.encodeWithSelector(
                IEngenBadges.mintBadges.selector,
                _getChainDeployment("KintoWallet-admin"),
                ids
            ), 
            address(proxy),
            deployerPrivateKey
        );
        */

    }
}