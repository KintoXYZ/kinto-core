// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "@aa/interfaces/IEntryPoint.sol";

import "../../../src/interfaces/IKintoWallet.sol";

import "../../../src/wallet/KintoWallet.sol";
import "../../../src/sample/Counter.sol";

import {UserOp} from "../../helpers/UserOp.sol";
import {AATestScaffolding} from "../../helpers/AATestScaffolding.sol";

contract ExecuteBatchTest is AATestScaffolding, UserOp {
    uint256[] privateKeys;

    // constants
    uint256 constant SIG_VALIDATION_FAILED = 1;

    // events
    event UserOperationRevertReason(
        bytes32 indexed userOpHash, address indexed sender, uint256 nonce, bytes revertReason
    );
    event KintoWalletInitialized(IEntryPoint indexed entryPoint, address indexed owner);
    event WalletPolicyChanged(uint256 newPolicy, uint256 oldPolicy);
    event RecovererChanged(address indexed newRecoverer, address indexed recoverer);

    function setUp() public {
        deployAAScaffolding(_owner, 1, _kycProvider, _recoverer);

        // Add paymaster to _kintoWallet
        _fundPaymasterForContract(address(_kintoWallet));

        // Default tests to use 1 private key for simplicity
        privateKeys = new uint256[](1);

        // Default tests to use _ownerPk unless otherwise specified
        privateKeys[0] = _ownerPk;
    }

    function testUp() public {
        assertEq(_kintoWallet.owners(0), _owner);
        assertEq(_entryPoint.walletFactory(), address(_walletFactory));
    }

    /* ============ One Signer Account Transaction Tests (executeBatch) ============ */

    function testExecuteBatch() public {
        // deploy the counter contract
        Counter counter = new Counter();
        assertEq(counter.count(), 0);

        // fund paymaster for Counter contract
        _fundSponsorForApp(address(counter));

        registerApp(_owner, "test", address(counter));

        // prep batch
        address[] memory targets = new address[](3);
        targets[0] = address(_kintoWallet);
        targets[1] = address(counter);
        targets[2] = address(counter);

        uint256[] memory values = new uint256[](3);
        values[0] = 0;
        values[1] = 0;
        values[2] = 0;

        bytes[] memory calls = new bytes[](3);

        address[] memory apps = new address[](1);
        apps[0] = address(counter);

        bool[] memory flags = new bool[](1);
        flags[0] = true;

        // 3 calls batch: whitelistApp and increment counter (two times)
        calls[0] = abi.encodeWithSignature("whitelistApp(address[],bool[])", apps, flags);
        calls[1] = abi.encodeWithSignature("increment()");
        calls[2] = abi.encodeWithSignature("increment()");

        OperationParamsBatch memory opParams = OperationParamsBatch({targets: targets, values: values, bytesOps: calls});
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = _createUserOperation(
            address(_kintoWallet), _kintoWallet.getNonce(), privateKeys, opParams, address(_paymaster)
        );

        // send all transactions via batch
        _entryPoint.handleOps(userOps, payable(_owner));
        assertEq(counter.count(), 2);
    }

    function testExecuteBatch_RevertWhen_TargetsBelongToDifferentApps() public {
        // deploy the counter contract
        Counter counter = new Counter();
        Counter counter2 = new Counter();
        assertEq(counter.count(), 0);
        assertEq(counter2.count(), 0);

        // fund paymaster for Counter contract
        _fundSponsorForApp(address(counter));

        registerApp(_owner, "counter app", address(counter));
        registerApp(_owner, "counter2 app", address(counter2));

        // prep batch
        address[] memory targets = new address[](3);
        targets[0] = address(_kintoWallet);
        targets[1] = address(counter);
        targets[2] = address(counter2);

        uint256[] memory values = new uint256[](3);
        values[0] = 0;
        values[1] = 0;
        values[2] = 0;

        address[] memory apps = new address[](1);
        apps[0] = address(counter);

        bool[] memory flags = new bool[](1);
        flags[0] = true;

        // 3 calls batch: whitelistApp, increment counter and increment counter2
        bytes[] memory calls = new bytes[](3);
        calls[0] = abi.encodeWithSignature("whitelistApp(address[],bool[])", apps, flags);
        calls[1] = abi.encodeWithSignature("increment()");
        calls[2] = abi.encodeWithSignature("increment()");

        // send all transactions via batch
        OperationParamsBatch memory opParams = OperationParamsBatch({targets: targets, values: values, bytesOps: calls});
        UserOperation memory userOp = _createUserOperation(
            address(_kintoWallet), _kintoWallet.getNonce(), privateKeys, opParams, address(_paymaster)
        );
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = userOp;

        // execute the transaction via the entry point

        // prepare expected error message
        uint256 expectedOpIndex = 0; // Adjust as needed
        string memory expectedMessage = "AA33 reverted";
        bytes memory additionalMessage =
            abi.encodePacked("SP: executeBatch targets must be sponsored by the contract or be the sender wallet");
        bytes memory expectedAdditionalData = abi.encodeWithSelector(
            bytes4(keccak256("Error(string)")), // Standard error selector
            additionalMessage
        );

        // encode the entire revert reason
        bytes memory expectedRevertReason = abi.encodeWithSignature(
            "FailedOpWithRevert(uint256,string,bytes)", expectedOpIndex, expectedMessage, expectedAdditionalData
        );

        vm.expectRevert(expectedRevertReason);
        _entryPoint.handleOps(userOps, payable(_owner));
    }

    // we want to test that we can execute a batch of user ops where all targets are app children
    // except for the first and the last ones which are the wallet itself
    function testExecuteBatch_TopAndBottomWalletOps() public {
        // deploy the counter contract
        Counter counter = new Counter();
        Counter counterRelatedContract = new Counter();
        assertEq(counter.count(), 0);

        // fund paymaster for Counter contract
        _fundSponsorForApp(address(counter));

        address[] memory appContracts = new address[](1);
        appContracts[0] = address(counterRelatedContract);
        registerApp(_owner, "counter app", address(counter), appContracts);

        // prep batch
        address[] memory targets = new address[](4);
        targets[0] = address(_kintoWallet);
        targets[1] = address(counter);
        targets[2] = address(counterRelatedContract);
        targets[3] = address(_kintoWallet);

        uint256[] memory values = new uint256[](4);
        values[0] = 0;
        values[1] = 0;
        values[2] = 0;
        values[3] = 0;

        // whitelistApp params
        address[] memory apps = new address[](1);
        apps[0] = address(counter);

        bool[] memory flags = new bool[](1);
        flags[0] = true;

        // 4 calls batch: whitelistApp, increment counter and increment counter2 and whitelistApp
        bytes[] memory calls = new bytes[](4);
        calls[0] = abi.encodeWithSignature("whitelistApp(address[],bool[])", apps, flags);
        calls[1] = abi.encodeWithSignature("increment()");
        calls[2] = abi.encodeWithSignature("increment()");
        calls[3] = abi.encodeWithSignature("whitelistApp(address[],bool[])", apps, flags);

        // send all transactions via batch
        OperationParamsBatch memory opParams = OperationParamsBatch({targets: targets, values: values, bytesOps: calls});
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = _createUserOperation(
            address(_kintoWallet), _kintoWallet.getNonce(), privateKeys, opParams, address(_paymaster)
        );

        // execute the transaction via the entry point
        _entryPoint.handleOps(userOps, payable(_owner));
        assertEq(counter.count(), 1);
        assertEq(counterRelatedContract.count(), 1);
    }
}
