// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {UserOp} from "./helpers/UserOp.sol";
import {AATestScaffolding} from "./helpers/AATestScaffolding.sol";

contract KintoEntryPointTest is AATestScaffolding, UserOp {
    uint256 _chainID = 1;

    function setUp() public {
        vm.chainId(_chainID);
        vm.startPrank(address(1));
        _owner.transfer(1e18);
        vm.stopPrank();
        deployAAScaffolding(_owner, 1, _kycProvider, _recoverer);
    }

    function testUp() public {
        assertEq(_entryPoint.walletFactory(), address(_walletFactory));
    }

    /* ============ Deployment Tests ============ */

    function testCannotResetWalletFactoryAddress() public {
        vm.startPrank(_owner);
        vm.expectRevert("AA36 wallet factory already set");
        _entryPoint.setWalletFactory(address(0));
        vm.stopPrank();
    }
}
