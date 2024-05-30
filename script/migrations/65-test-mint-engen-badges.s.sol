// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@kinto-core/tokens/EngenBadges.sol";
import "@kinto-core/interfaces/IKintoWallet.sol";
import "../../test/helpers/ArtifactsReader.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";

contract MintEngenBadgesScript is MigrationHelper {
    function run() public override {
        super.run();

        address engenBadgesAddr = _getChainDeployment("EngenBadges");
        IKintoWallet adminWallet = IKintoWallet(_getChainDeployment("KintoWallet-admin"));

        etchWallet(0xe1FcA7f6d88E30914089b600A73eeF72eaC7f601);
        // replaceOwner(adminWallet, 0x4632F4120DC68F225e7d24d973Ee57478389e9Fd);
        // replaceOwner(adminWallet, _getChainDeployment("EntryPoint"));

        uint256[] memory ids = new uint256[](1);
        ids[0] = 42;

        uint256[] memory privKeys = new uint256[](2);
        privKeys[0] = deployerPrivateKey;
        privKeys[1] = LEDGER;
        _handleOps(
            abi.encodeWithSelector(EngenBadges.mintBadges.selector, address(adminWallet), ids),
            address(adminWallet),
            engenBadgesAddr,
            0,
            address(0),
            privKeys
        );
    }
}
