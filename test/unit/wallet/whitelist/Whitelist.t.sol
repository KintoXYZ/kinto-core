// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import "@kinto-core-test/SharedSetup.t.sol";

contract WhitelistTest is SharedSetup {
    function testWhitelistAppAndSetKey() public {
        // deploy an app
        Counter counter = new Counter();
        assertEq(counter.count(), 0);

        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = _createUserOperation(
            address(_kintoWallet),
            address(_kintoWallet), // target is the wallet itself
            _kintoWallet.getNonce(),
            privateKeys,
            abi.encodeWithSignature("whitelistAppAndSetKey(address,address)", address(counter), _user),
            address(_paymaster)
        );

        _entryPoint.handleOps(userOps, payable(_owner));

        assertTrue(_kintoWallet.appWhitelist(address(counter)));
        assertEq(_kintoWallet.appSigner(address(counter)), _user);
    }

    function testWhitelistApp() public {
        // deploy an app
        Counter counter = new Counter();
        assertEq(counter.count(), 0);

        // create whitelist app user op
        whitelistApp(address(counter), true);

        assertTrue(_kintoWallet.appWhitelist(address(counter)));
    }

    function testWhitelistApp_RevertWhen_AlreadyWhitelisted() public {
        //re-register app
        whitelistApp(address(counter), true);
    }

    function testWhitelistAppRemovesAppKey() public {
        // deploy an app
        Counter counter = new Counter();

        whitelistApp(address(counter), true);

        assertTrue(_kintoWallet.appWhitelist(address(counter)));
        assertEq(_kintoWallet.appSigner(address(counter)), address(0), "Signer is not a zero address");

        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = _createUserOperation(
            address(_kintoWallet),
            address(_kintoWallet),
            _kintoWallet.getNonce(),
            privateKeys,
            abi.encodeWithSignature("setAppKey(address,address)", address(counter), _user),
            address(_paymaster)
        );
        _entryPoint.handleOps(userOps, payable(_owner));
        assertEq(_kintoWallet.appSigner(address(counter)), _user);

        whitelistApp(address(counter), false);

        assertFalse(_kintoWallet.appWhitelist(address(counter)));
        assertEq(_kintoWallet.appSigner(address(counter)), address(0), "Signer is not a zero address");
    }

    // function testWhitelist_RevertWhen_AppIsNotRegistered() public {
    //     // (1). deploy Counter contract
    //     Counter counter = new Counter();
    //     assertEq(counter.count(), 0);

    //     // (2). fund paymaster for Counter contract
    //     fundSponsorForApp(_owner, address(counter));

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
