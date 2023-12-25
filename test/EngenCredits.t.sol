// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import '../src/tokens/EngenCredits.sol';
import 'forge-std/Test.sol';
import 'forge-std/console.sol';
import {UUPSProxy} from './helpers/UUPSProxy.sol';

contract EngenCreditsV2 is EngenCredits {
    function newFunction() external pure returns (uint256) {
        return 1;
    }
    constructor() EngenCredits() {}
}

contract EngenCreditsTest is Test {
    EngenCredits _engenCredits;
    EngenCreditsV2 _engenCreditsV2;
    UUPSProxy _proxy;

    address _owner = address(1);
    address _user = vm.addr(3);
    address _user2 = vm.addr(4);

    function setUp() public {
        vm.startPrank(_owner);

        EngenCredits _imp = new EngenCredits{salt: 0}();
        // deploy _proxy contract and point it to _implementation
        _proxy = new UUPSProxy{salt: 0 }(address(_imp), '');
        // wrap in ABI to support easier calls
        _engenCredits = EngenCredits(address(_proxy));
        // Initialize kyc viewer _proxy
        _engenCredits.initialize();
        vm.stopPrank();
    }

    function testUp() public {
        assertEq(_engenCredits.totalSupply(), 0);
        assertEq(_engenCredits.owner(), _owner);
        assertEq(_engenCredits.transfersEnabled(), false);
        assertEq(_engenCredits.burnsEnabled(), false);
    }

    /* ============ Upgrade Tests ============ */

    function testOwnerCanUpgradeEngen() public {
        vm.startPrank(_owner);
        EngenCreditsV2 _implementationV2 = new EngenCreditsV2();
        _engenCredits.upgradeTo(address(_implementationV2));
        // re-wrap the _proxy
        _engenCreditsV2 = EngenCreditsV2(address(_engenCredits));
        assertEq(_engenCreditsV2.newFunction(), 1);
        vm.stopPrank();
    }

    function testFailOthersCannotUpgrade() public {
        EngenCreditsV2 _implementationV2 = new EngenCreditsV2();
        _engenCredits.upgradeTo(address(_implementationV2));
        // re-wrap the _proxy
        _engenCreditsV2 = EngenCreditsV2(address(_engenCredits));
        assertEq(_engenCreditsV2.newFunction(), 1);
    }

    /* ============ Token Tests ============ */

    function testOwnerCanMint() public {
        vm.startPrank(_owner);
        _engenCredits.mint(_user, 100);
        assertEq(_engenCredits.balanceOf(_user), 100);
        vm.stopPrank();
    }

    function testOthersCannotMint() public {
        vm.expectRevert('Ownable: caller is not the owner');
        _engenCredits.mint(_user, 100);
        assertEq(_engenCredits.balanceOf(_user), 0);
    }

    function testNobodyCanTransfer() public {
        vm.startPrank(_owner);
        _engenCredits.mint(_owner, 100);
        vm.expectRevert('Engen Transfers Disabled');
        _engenCredits.transfer(_user2, 100);
        vm.stopPrank();
    }

    function testNobodyCanBurn() public {
        vm.startPrank(_owner);
        _engenCredits.mint(_user, 100);
        vm.expectRevert('Engen Transfers Disabled');
        _engenCredits.burn(100);
        vm.stopPrank();
    }

    function testCanTransferAfterSettingFlag() public {
        vm.startPrank(_owner);
        _engenCredits.mint(_owner, 100);
        _engenCredits.setTransfersEnabled(true);
        _engenCredits.transfer(_user2, 100);
        assertEq(_engenCredits.balanceOf(_user2), 100);
        assertEq(_engenCredits.balanceOf(_owner), 0);
        vm.stopPrank();
    }

    function testCanBurnAfterSettingFlag() public {
        vm.startPrank(_owner);
        _engenCredits.mint(_owner, 100);
        _engenCredits.setBurnsEnabled(true);
        _engenCredits.burn(100);
        assertEq(_engenCredits.balanceOf(_owner), 0);
        vm.stopPrank();
    }

}
