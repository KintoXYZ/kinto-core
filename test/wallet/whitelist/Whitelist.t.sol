// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/console.sol";
import "../../SharedSetup.t.sol";

contract WhitelistTest is SharedSetup {
    /* ============ Whitelist ============ */

    function testWhitelistApp() public {
        // deploy an app
        Counter counter = new Counter();
        assertEq(counter.count(), 0);

        // create whitelist app user op
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = _whitelistAppOp(
            privateKeys, address(_kintoWallet), _kintoWallet.getNonce(), address(counter), address(_paymaster)
        );

        _entryPoint.handleOps(userOps, payable(_owner));

        assertTrue(_kintoWallet.appWhitelist(address(counter)));
    }

    function testWhitelistApp_RevertWhen_AlreadyWhitelisted() public {
        //re-register app
        whitelistApp(address(counter), true);
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
