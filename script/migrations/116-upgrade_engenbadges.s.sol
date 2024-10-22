// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../../src/tokens/EngenBadges.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import "@kinto-core-script/migrations/const.sol";

contract Script is MigrationHelper {
    function run() public override {
        super.run();

        bytes memory bytecode = abi.encodePacked(type(EngenBadges).creationCode);
        address impl = _deployImplementationAndUpgrade("EngenBadges", "V3", bytecode, keccak256("V3"));

        EngenBadges engenBadges = EngenBadges(_getChainDeployment("EngenBadges"));
        uint256[] memory balances = engenBadges.getAllBadges(_getChainDeployment("KintoWallet-admin"), 10);
        assertEq(balances[0], 0);
        assertEq(balances[1], 1);
        assertEq(balances[10], 1);
        assertEq(engenBadges.uri(1), "https://kinto.xyz/api/v1/get-badge-nft/{id}");
        assertEq(engenBadges.name(), "Engen Badges");

        saveContractAddress("EngenBadgesV3-impl", impl);
    }
}
