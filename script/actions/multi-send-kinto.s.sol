// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../../src/wallet/KintoWalletFactory.sol";
import "../../src/wallet/KintoWallet.sol";
import "../../src/sample/Counter.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import {ERC20Multisender} from "@kinto-core-script/utils/ERC20MultiSender.sol";
import {stdJson} from "forge-std/StdJson.sol";

contract Script is MigrationHelper {
    using stdJson for string;

    address[] users;

    function run() public override {
        super.run();

        string memory userFile = vm.envString("USERS_FILE");

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
    }
}
