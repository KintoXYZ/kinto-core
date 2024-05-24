// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@kinto-core/tokens/EngenBadges.sol";
import "../../test/helpers/ArtifactsReader.sol";
import "@kinto-core-script/utils/MigrationHelper.sol";

import "@kinto-core-script/migrations/const.sol";

contract MintEngenBadgesScript is MigrationHelper, Constants {
    using ECDSAUpgradeable for bytes32;

    function run() public override {
        super.run();

        address engenBadgesAddr = _getChainDeployment("EngenBadges");

        uint256[] memory ids = new uint256[](1);
        ids[0] = 42;

        _handleOps(
            abi.encodeWithSelector(EngenBadges.mintBadges.selector, _getChainDeployment("KintoWallet-admin"), ids),
            engenBadgesAddr,
            TREZOR
        );
    }
}
