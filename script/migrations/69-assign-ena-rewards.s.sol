// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {stdJson} from "forge-std/StdJson.sol";

import "../../src/wallet/KintoWallet.sol";
import "@kinto-core-script/utils/MigrationHelper.sol";
import "@kinto-core/bridger/BridgerL2.sol";

contract AssignWstEthRefundsScript is MigrationHelper {
    using stdJson for string;
    function run() public override {
        super.run();

        BridgerL2 bridgerL2 = BridgerL2(_getChainDeployment("BridgerL2"));

        string memory json = vm.readFile('./script/data/enarewardsfinal.json');
        string[] memory keys = vm.parseJsonKeys(json, "$");
        address[] memory users = new address[](keys.length);
        uint256[] memory amounts = new uint256[](keys.length);
        for (uint256 index = 0; index < keys.length; index++) {
            uint256 amount = json.readUint(string.concat('.',keys[index]));
            address user = vm.parseAddress(keys[index]);
            console2.log('address', user);
            console2.log('amount:', amount);
            users[index] = user;
            amounts[index] = amount;
        }

        bytes memory selectorAndParams =
            abi.encodeWithSelector(BridgerL2.assignENARewards.selector, users, amounts);
        _handleOps(selectorAndParams, address(bridgerL2), deployerPrivateKey);

        require(false, "Do not run");
    }
}
