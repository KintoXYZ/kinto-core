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

    function testMultipleTransactionsExecuteBatchPaymaster() public {
        vm.startPrank(_owner);
        // Let's deploy the counter contract
        Counter counter = new Counter();
        assertEq(counter.count(), 0);
        uint256 nonce = _kintoWallet.getNonce();
        vm.stopPrank();
        registerApp(_owner, "test", address(counter));
        vm.startPrank(_owner);
        _fundPaymasterForContract(address(counter));
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
        calls[0] = abi.encodeWithSignature("whitelistApp(address[],bool[])", apps, flags);
        calls[1] = abi.encodeWithSignature("increment()");
        calls[2] = abi.encodeWithSignature("increment()");

        OperationParamsBatch memory opParams = OperationParamsBatch({targets: targets, values: values, bytesOps: calls});
        UserOperation memory userOp =
            _createUserOperation(address(_kintoWallet), nonce, privateKeys, opParams, address(_paymaster));
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = userOp;
        // Execute the transaction via the entry point
        _entryPoint.handleOps(userOps, payable(_owner));
        assertEq(counter.count(), 2);
        vm.stopPrank();
    }

    function test_RevertWhen_MultipleTransactionsExecuteBatchPaymasterRefuses() public {
        // deploy the counter contract
        Counter counter = new Counter();
        Counter counter2 = new Counter();
        assertEq(counter.count(), 0);
        assertEq(counter2.count(), 0);

        // only fund counter
        _fundPaymasterForContract(address(counter));

        registerApp(_owner, "test", address(counter));

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

        // we want to do 3 calls: whitelistApp, increment counter and increment counter2
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
}
