// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@kinto-core/interfaces/IKintoWallet.sol";

import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import {AccessManager} from "@openzeppelin-5.0.1/contracts/access/manager/AccessManager.sol";

import {stdJson} from "forge-std/StdJson.sol";
import "forge-std/Script.sol";
import "forge-std/console.sol";

contract AccessManagerExecuteScript is MigrationHelper {
    using stdJson for string;

    function run() public override {
        super.run();

        string memory json = vm.readFile("./script/data/multisig.json");

        address from = json.readAddress(string.concat(".", "from"));
        address to = json.readAddress(string.concat(".", "to"));
        address paymaster = json.readAddress(string.concat(".", "paymaster"));
        bytes memory data = json.readBytes(string.concat(".", "calldata"));
        uint256 value = json.readUint(string.concat(".", "value"));
        uint256 key = json.readUint(string.concat(".", "key"));

        address accessManager = _getChainDeployment("AccessManager");

        bytes memory managerCalldata = abi.encodeWithSelector(AccessManager.execute.selector, to, data);

        uint256[] memory privKeys = new uint256[](2);
        privKeys[0] = deployerPrivateKey;
        privKeys[1] = key;

        _handleOps(managerCalldata, from, accessManager, value, paymaster, privKeys);
    }
}
