// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console.sol";
import "../../KintoWallet.t.sol";

contract FunderTest is KintoWalletTest {
    /* ============ Funder Whitelist ============ */

    function testUp() public override {
        super.testUp();

        assertEq(_kintoWallet.isFunderWhitelisted(_owner), true);
        assertEq(_kintoWallet.isFunderWhitelisted(_user), false);
        assertEq(_kintoWallet.isFunderWhitelisted(_user2), false);
    }

    function testSetFunderWhitelist() public {
        vm.startPrank(_owner);
        address[] memory funders = new address[](1);
        funders[0] = address(23);
        uint256 nonce = _kintoWallet.getNonce();
        bool[] memory flags = new bool[](1);
        flags[0] = true;
        UserOperation memory userOp = _createUserOperation(
            address(_kintoWallet),
            address(_kintoWallet),
            nonce,
            privateKeys,
            abi.encodeWithSignature("setFunderWhitelist(address[],bool[])", funders, flags),
            address(_paymaster)
        );
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = userOp;
        // Execute the transaction via the entry point
        _entryPoint.handleOps(userOps, payable(_owner));
        assertEq(_kintoWallet.isFunderWhitelisted(address(23)), true);
        vm.stopPrank();
    }
}
