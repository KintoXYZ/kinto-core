// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@kinto-core/tokens/EngenBadges.sol";

import {AccessManager} from "@openzeppelin-5.0.1/contracts/access/manager/AccessManager.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import {KintoID} from "@kinto-core/KintoID.sol";
import {IKintoWalletFactory} from "@kinto-core/interfaces/IKintoWalletFactory.sol";
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
    bytes[] selectorAndParams;

    function run() public override {
        super.run();

        string memory userFile = vm.envString("WALLETS_FILE");

        address factory = _getChainDeployment("KintoWalletFactory");
        address accessManager = _getChainDeployment("AccessManager");

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
            bytes memory managerCalldata = abi.encodeWithSelector(
                AccessManager.execute.selector,
                factory,
                abi.encodeWithSelector(IKintoWalletFactory.approveWalletRecovery.selector, user)
            );
            selectorAndParams.push(managerCalldata);
        }
        _handleOpsBatch(selectorAndParams, accessManager);

        for (uint256 index = 0; index < users.length; index++) {
            assertEq(
                IKintoWalletFactory(factory).adminApproved(users[index]),
                true,
                "Failed to approve recovery a sanction on the user"
            );
        }
    }
}
