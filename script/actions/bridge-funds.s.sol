// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {IBridge} from "@kinto-core/interfaces/bridger/IBridge.sol";

import "@kinto-core-script/utils/MigrationHelper.sol";

import {stdJson} from "forge-std/StdJson.sol";
import "forge-std/Script.sol";
import "forge-std/console.sol";

contract BridgeFundsScript is MigrationHelper {
    using stdJson for string;

    function broadcast(address) internal override {
        string memory json = vm.readFile("./script/data/weEthKintoToEthereumBridge.json");

        address from = json.readAddress(string.concat(".", "from"));
        address vault = json.readAddress(string.concat(".", "vault"));
        address receiver = json.readAddress(string.concat(".", "receiver"));
        uint256 amount = json.readUint(string.concat(".", "amount"));
        uint256 msgGasLimit = json.readUint(string.concat(".", "msgGasLimit"));
        address connector = json.readAddress(string.concat(".", "connector"));
        bytes memory execPayload = json.readBytes(string.concat(".", "execPayload"));
        bytes memory options = json.readBytes(string.concat(".", "options"));
        uint256 gasFee = json.readUint(string.concat(".", "gasFee"));

        if (amount == 0) {}

        uint256[] memory privKeys = new uint256[](2);
        privKeys[0] = deployerPrivateKey;
        privKeys[1] = LEDGER;
        _handleOps(
            abi.encodeWithSelector(
                IBridge.bridge.selector, receiver, amount, msgGasLimit, connector, execPayload, options
            ),
            from,
            vault,
            gasFee,
            address(0),
            privKeys
        );
    }

    function validate(address) internal view override {}
}
