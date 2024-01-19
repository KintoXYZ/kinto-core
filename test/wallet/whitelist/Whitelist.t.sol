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

contract WhitelistTest is AATestScaffolding, UserOp {
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

    /* ============ Whitelist ============ */

    function testWhitelistRegisteredApp() public {
        // (1). deploy Counter contract
        Counter counter = new Counter();
        assertEq(counter.count(), 0);

        // (2). fund paymaster for Counter contract
        _fundPaymasterForContract(address(counter));

        // (3). register app
        registerApp(_owner, "test", address(counter));

        // (4). Create whitelist app user op
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = _whitelistAppOp(
            privateKeys, address(_kintoWallet), _kintoWallet.getNonce(), address(counter), address(_paymaster)
        );

        // (5). execute the transaction via the entry point
        _entryPoint.handleOps(userOps, payable(_owner));
    }

    // function testWhitelist_revertWhen_AppNotRegistered() public {
    //     // (1). deploy Counter contract
    //     Counter counter = new Counter();
    //     assertEq(counter.count(), 0);

    //     // (2). fund paymaster for Counter contract
    //     _fundPaymasterForContract(address(counter));

    //     // (3). Create whitelist app user op
    //     UserOperation[] memory userOps = new UserOperation[](1);
    //     userOps[0] = _whitelistAppOp(
    //         privateKeys, address(_kintoWallet), _kintoWallet.getNonce(), address(counter), address(_paymaster)
    //     );

    //     // (4). execute the transaction via the entry point and expect a revert event
    //     vm.expectEmit(true, true, true, false);
    //     emit UserOperationRevertReason(
    //         _entryPoint.getUserOpHash(userOps[0]), userOps[0].sender, userOps[0].nonce, bytes("")
    //     );
    //     vm.recordLogs();
    //     _entryPoint.handleOps(userOps, payable(_owner));
    //     assertRevertReasonEq("KW-apw: app must be registered");
    // }
}
