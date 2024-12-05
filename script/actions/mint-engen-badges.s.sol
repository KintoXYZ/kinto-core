// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@kinto-core/tokens/EngenBadges.sol";

import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import {IKintoWallet} from "@kinto-core/interfaces/IKintoWallet.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import "@kinto-core-test/helpers/ArrayHelpers.sol";

import {stdJson} from "forge-std/StdJson.sol";
import "forge-std/Script.sol";
import "forge-std/console.sol";

contract MintEngenBadgesScript is MigrationHelper {
    using stdJson for string;
    using Strings for *;
    using ArrayHelpers for *;

    address[] users;
    uint256[][] mintIds;

    function run() public override {
        super.run();

        string memory userFile = vm.envString("USERS_FILE");

        uint256 id = vm.envUint("BADGE_ID");
        console2.log("BADGE_ID:", id);

        EngenBadges badges = EngenBadges(_getChainDeployment("EngenBadges"));

        while (true) {
            string memory addrStr = vm.readLine(userFile);
            // if empty string then end of the file
            if (addrStr.equal("")) {
                break;
            }
            address addr = vm.parseAddress(addrStr);
            // if user have a badge, then do not mint
            if (badges.balanceOf(addr, id) > 0) {
                console2.log("addr has a badge already:", addr);
                continue;
            }
            console2.log("addr:", addr);
            users.push(addr);
            uint256[] memory ids = new uint256[](1);
            ids[0] = id;
            mintIds.push(ids);
        }

        uint256[] memory privKeys = new uint256[](2);
        privKeys[0] = deployerPrivateKey;
        privKeys[1] = hardwareWalletType;

        uint256 batchSize = 100;
        uint256 totalBatches = (users.length + batchSize - 1) / batchSize;

        for (uint256 batchIndex = 0; batchIndex < totalBatches; batchIndex++) {
            uint256 start = batchIndex * batchSize;
            uint256 end = start + batchSize;
            if (end > users.length) {
                end = users.length;
            }

            address[] memory batchUsers = new address[](end - start);
            uint256[][] memory batchMintIds = new uint256[][](end - start);

            for (uint256 i = start; i < end; i++) {
                batchUsers[i - start] = users[i];
                batchMintIds[i - start] = mintIds[i];
            }

            _handleOps(
                abi.encodeWithSelector(EngenBadges.mintBadgesBatch.selector, batchUsers, batchMintIds),
                kintoAdminWallet,
                _getChainDeployment("EngenBadges"),
                0,
                address(0),
                privKeys
            );
        }

        for (uint256 index = 0; index < users.length; index++) {
            assertEq(badges.balanceOf(users[index], id), 1, "Has more than one badge");
        }
    }
}
