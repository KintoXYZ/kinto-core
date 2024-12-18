// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {IEntryPoint} from "@aa/core/BaseAccount.sol";
import {PackedUserOperation} from "@aa/interfaces/PackedUserOperation.sol";

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
        bytes32 accountGasLimits = json.readBytes32(".inflatedOp.accountGasLimits");
        bytes32 gasFees = json.readBytes32(".inflatedOp.gasFees");
        uint256 preVerificationGas = json.readUint(".inflatedOp.preVerificationGas");
        bytes memory paymasterAndData = json.readBytes(".inflatedOp.paymasterAndData");
        bytes memory signature = json.readBytes(".inflatedOp.signature");

        PackedUserOperation[] memory userOps = new PackedUserOperation[](1);
        userOps[0] = PackedUserOperation({
            sender: sender,
            nonce: nonce,
            initCode: initCode,
            callData: callData,
            preVerificationGas: preVerificationGas,
            accountGasLimits: accountGasLimits,
            gasFees: gasFees,
            paymasterAndData: paymasterAndData,
            signature: signature
        });
        vm.broadcast(deployerPrivateKey);
        IEntryPoint(_getChainDeployment("EntryPoint")).handleOps(userOps, payable(sender));
    }
}
