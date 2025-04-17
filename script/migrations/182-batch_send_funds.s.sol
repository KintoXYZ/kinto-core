// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Treasury} from "@kinto-core/treasury/Treasury.sol";
import {AccessManager} from "@openzeppelin-5.0.1/contracts/access/manager/AccessManager.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import {IERC20} from "@openzeppelin-5.0.1/contracts/interfaces/IERC20.sol";

import "forge-std/console2.sol";

contract BatchSendFundsScript is MigrationHelper {
    using Strings for *;

    address[] users;

    function run() public override {
        super.run();

        address accessManager = (_getChainDeployment("AccessManager"));

        // Fixed amount per recipient: 30 $K tokens
        uint256 amountPerRecipient = 30e18;

        while (true) {
            string memory addrStr = vm.readLine("./script/data/oshigaru.txt");
            // if empty string then end of the file
            if (addrStr.equal("")) {
                break;
            }
            address addr = vm.parseAddress(addrStr);
            console2.log("addr:", addr);
            users.push(addr);
        }

        // Get the Kinto token address
        address kintoToken = _getChainDeployment("KINTO");

        // Get the Treasury address
        address treasuryAddress = _getChainDeployment("Treasury");

        // Calculate total amount needed
        uint256 totalAmount = amountPerRecipient * users.length;
        console2.log("Total Recipients:", users.length);
        console2.log("Amount per recipient:", amountPerRecipient);
        console2.log("Total amount needed:", totalAmount);

        // Check if Treasury has enough tokens
        uint256 treasuryBalance = IERC20(kintoToken).balanceOf(treasuryAddress);
        console2.log("Treasury balance:", treasuryBalance);

        // Prepare arrays for Treasury.batchSendFunds
        bytes[] memory calldatas = new bytes[](users.length);
        address[] memory tos = new address[](users.length);
        uint256[] memory values = new uint256[](users.length);

        for (uint256 i = 0; i < users.length; i++) {
            bytes memory treasuryCalldata =
                abi.encodeWithSelector(Treasury.sendFunds.selector, kintoToken, amountPerRecipient, users[i]);
            calldatas[i] = abi.encodeWithSelector(AccessManager.execute.selector, treasuryAddress, treasuryCalldata);
            tos[i] = accessManager;
            values[i] = 0;
        }

        _handleOpsBatchExecute(calldatas, tos, values);

        console2.log("Treasury funds distribution completed successfully!");
    }
}
