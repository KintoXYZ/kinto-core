// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console.sol";
import "../../SharedSetup.t.sol";

contract ExecuteTest is SharedSetup {
    /* ============ handleOps tests ============ */

    function testExecute_WhenPaymaster() public {
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = _createUserOperation(
            address(_kintoWallet),
            address(counter),
            _kintoWallet.getNonce(),
            privateKeys,
            abi.encodeWithSignature("increment()"),
            address(_paymaster)
        );

        // execute the transactions via the entry point
        _entryPoint.handleOps(userOps, payable(_owner));
        assertEq(counter.count(), 1);
    }

    function testExecute_RevertWhen_NoPaymasterNorPrefund() public {
        // send a transaction to the counter contract through our wallet without a paymaster and without prefunding the wallet
        UserOperation memory userOp = _createUserOperation(
            address(_kintoWallet),
            address(counter),
            _kintoWallet.getNonce(),
            privateKeys,
            abi.encodeWithSignature("increment()")
        );
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = userOp;

        vm.expectRevert(abi.encodeWithSignature("FailedOp(uint256,string)", 0, "AA21 didn't pay prefund"));
        _entryPoint.handleOps(userOps, payable(_owner));
    }

    function testExecute_WhenPrefund() public {
        // prefund wallet
        vm.deal(address(_kintoWallet), 1 ether);

        // send op without a paymaster but prefunding the wallet
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = _createUserOperation(
            address(_kintoWallet),
            address(counter),
            _kintoWallet.getNonce(),
            privateKeys,
            abi.encodeWithSignature("increment()")
        );

        _entryPoint.handleOps(userOps, payable(_owner));
        assertEq(counter.count(), 1);
    }

    function testExecute_WhenMultipleOps_WhenPaymaster() public {
        uint256 nonce = _kintoWallet.getNonce();
        UserOperation[] memory userOps = new UserOperation[](2);
        userOps[0] = _createUserOperation(
            address(_kintoWallet),
            address(counter),
            nonce,
            privateKeys,
            abi.encodeWithSignature("increment()"),
            address(_paymaster)
        );

        userOps[1] = _createUserOperation(
            address(_kintoWallet),
            address(counter),
            nonce + 1,
            privateKeys,
            abi.encodeWithSignature("increment()"),
            address(_paymaster)
        );

        _entryPoint.handleOps(userOps, payable(_owner));
        assertEq(counter.count(), 2);
    }

    function testExecute_RevertWhen_AppIsNotWhitelisted() public {
        // remove app from whitelist
        whitelistApp(address(counter), false);

        // create Counter increment user op
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = _createUserOperation(
            address(_kintoWallet),
            address(counter),
            _kintoWallet.getNonce(),
            privateKeys,
            abi.encodeWithSignature("increment()"),
            address(_paymaster)
        );

        // execute transaction
        vm.expectEmit(true, true, true, false);
        emit UserOperationRevertReason(
            _entryPoint.getUserOpHash(userOps[0]), userOps[0].sender, userOps[0].nonce, bytes("")
        );
        vm.recordLogs();
        _entryPoint.handleOps(userOps, payable(_owner));
        assertRevertReasonEq("KW: contract not whitelisted");
        assertEq(counter.count(), 0);
    }

    /* ============ handleAggregatedOps tests ============ */

    function testExecute_WhenPaymaster_WhenHandleAggregatedOps() public {
        setPublicKey(_blsPublicKey);

        // single signer
        address[] memory owners = new address[](1);
        owners[0] = _owner;
        resetSigners(owners, _kintoWallet.SINGLE_SIGNER());

        IEntryPoint.UserOpsPerAggregator[] memory userOpsPerAggregator = new IEntryPoint.UserOpsPerAggregator[](1);
        userOpsPerAggregator[0].aggregator = _aggregator;
        userOpsPerAggregator[0].userOps = new UserOperation[](1);

        UserOperation memory userOp = _createUserOperation(
            address(_kintoWallet),
            address(counter),
            _kintoWallet.getNonce(),
            privateKeys,
            abi.encodeWithSignature("increment()"),
            address(_paymaster)
        );
        userOp.signature = bytes("0x");

        userOpsPerAggregator[0].userOps[0] = userOp;

        // NOTE: since we can't test the BLS signature using foundry, I'm running this test to generate the message
        // (which is split into two parts) and then I use the signMessage.js to sign the message and get the signature
        console.log("Message to sign (part 0)", _aggregator.userOpToMessage(userOp)[0]);
        console.log("Message to sign (part 1)", _aggregator.userOpToMessage(userOp)[1]);

        // Once signed, I can replace this signature with the one generated by the signMessage.js and re-run the test.
        // TODO: maybe just easier to have a hardhat test for this so we can do everything on the same test
        bytes memory signature =
            hex"1b2e272437d02d2e3c9cb35d08dc8e99611649fb29cbf6889bbce647cc09320c0be757bbda1b49bf55ee954a77ff01a5f78667949f5a89e311eef7bf4493d91f";
        userOpsPerAggregator[0].signature = signature;

        // execute the transactions via the entry point
        _entryPoint.handleAggregatedOps(userOpsPerAggregator, payable(_owner));
    }
}
