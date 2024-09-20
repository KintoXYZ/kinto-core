// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import "@kinto-core-test/SharedSetup.t.sol";

contract WhitelistTest is SharedSetup {
    function testWhitelistAppAndSetKey() public {
        Counter counter = new Counter();

        vm.prank(address(_kintoWallet));
        _kintoWallet.whitelistAppAndSetKey(address(counter), _user);

        assertTrue(_kintoWallet.appWhitelist(address(counter)));
        assertEq(_kintoWallet.appSigner(address(counter)), _user);
    }

    function testWhitelistApp() public {
        Counter counter = new Counter();

        whitelistApp(address(counter), true);

        assertTrue(_kintoWallet.appWhitelist(address(counter)));
        assertTrue(_kintoWallet.isAppApproved(address(counter)));
    }

    function testWhitelistAppRemovesAppKey() public {
        Counter counter = new Counter();

        whitelistApp(address(counter), true);

        assertTrue(_kintoWallet.appWhitelist(address(counter)));
        assertEq(_kintoWallet.appSigner(address(counter)), address(0), "Signer is not a zero address");

        vm.prank(address(_kintoWallet));
        _kintoWallet.setAppKey(address(counter), _user);

        assertEq(_kintoWallet.appSigner(address(counter)), _user);

        whitelistApp(address(counter), false);

        assertFalse(_kintoWallet.appWhitelist(address(counter)));
        assertEq(_kintoWallet.appSigner(address(counter)), address(0), "Signer is not a zero address");
    }
}
