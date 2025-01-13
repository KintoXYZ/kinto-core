// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@kinto-core/tokens/EngenBadges.sol";

import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import {KintoID} from "@kinto-core/KintoID.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import "@kinto-core-test/helpers/ArrayHelpers.sol";

import {stdJson} from "forge-std/StdJson.sol";
import "forge-std/Script.sol";
import "forge-std/console.sol";

contract ConfirmSanctionScript is MigrationHelper {
    using stdJson for string;
    using Strings for *;
    using ArrayHelpers for *;

    address[] users;

    function run() public override {
        super.run();

        string memory userFile = vm.envString("USERS_FILE");

        KintoID kintoID = KintoID(_getChainDeployment("KintoID"));

        while (true) {
            string memory addrStr = vm.readLine(userFile);
            // if empty string then end of the file
            if (addrStr.equal("")) {
                break;
            }
            address addr = vm.parseAddress(addrStr);
            console2.log("addr:", addr);
            users.push(addr);
        }

        uint256[] memory privKeys = new uint256[](2);
        privKeys[0] = deployerPrivateKey;
        privKeys[1] = hardwareWalletType;

        for (uint256 index = 0; index < users.length; index++) {
            address user = users[index];

            _handleOps(
                abi.encodeWithSelector(KintoID.confirmSanction.selector, user),
                kintoAdminWallet,
                address(kintoID),
                0,
                address(0),
                privKeys
            );
        }

        for (uint256 index = 0; index < users.length; index++) {
            assertEq(kintoID.sanctionedAt(users[index]), 0, "Failed to confirm a sanction on the user");
        }
    }
}

