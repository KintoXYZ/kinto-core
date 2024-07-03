// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {IEntryPoint, UserOperation} from "@aa/core/BaseAccount.sol";

import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";

import {stdJson} from "forge-std/StdJson.sol";
import "forge-std/Script.sol";
import "forge-std/console2.sol";

contract SendUserOperationScript is MigrationHelper {
    using stdJson for string;

    function run() public override {
        super.run();

        string memory json = vm.readFile("./script/data/user-operation.json");

        address sender = json.readAddress(".inflatedOp.sender");
        uint256 nonce = json.readUint(".inflatedOp.nonce");
        bytes memory callData = json.readBytes(".inflatedOp.callData");
        bytes memory initCode = json.readBytes(".inflatedOp.initCode ");
        uint256 callGasLimit = json.readUint(".inflatedOp.callGasLimit");
        uint256 verificationGasLimit = json.readUint(".inflatedOp.verificationGasLimit");
        uint256 preVerificationGas = json.readUint(".inflatedOp.preVerificationGas");
        uint256 maxFeePerGas = json.readUint(".inflatedOp.maxFeePerGas");
        uint256 maxPriorityFeePerGas = json.readUint(".inflatedOp.maxPriorityFeePerGas");
        bytes memory paymasterAndData = json.readBytes(".inflatedOp.paymasterAndData");
        bytes memory signature = json.readBytes(".inflatedOp.signature");

        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = UserOperation({
            sender: sender,
            nonce: nonce,
            initCode: initCode,
            callData: callData,
            callGasLimit: callGasLimit,
            verificationGasLimit: verificationGasLimit,
            preVerificationGas: preVerificationGas,
            maxFeePerGas: maxFeePerGas,
            maxPriorityFeePerGas: maxPriorityFeePerGas,
            paymasterAndData: paymasterAndData,
            signature: signature
        });
        vm.broadcast(deployerPrivateKey);
        IEntryPoint(_getChainDeployment("EntryPoint")).handleOps(userOps, payable(sender));
    }
}
