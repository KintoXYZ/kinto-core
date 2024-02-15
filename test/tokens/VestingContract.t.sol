// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../../src/tokens/KintoToken.sol";
import "../../src/tokens/VestingContract.sol";
import "../SharedSetup.t.sol";

contract VestingContractTest is SharedSetup, Create2Helper {
    KintoToken _token;
    VestingContract _vestingContract;

    function setUp() public override {
        super.setUp();
        vm.startPrank(_owner);
        _token = new KintoToken();
        _vestingContract = new VestingContract(address(_token));
        _token.transfer(address(_vestingContract), _token.INITIAL_SUPPLY());
        vm.stopPrank();
    }

    function testUp() public override {
        super.testUp();
        assertEq(_token.balanceOf(address(_vestingContract)), _token.INITIAL_SUPPLY());
        assertEq(_vestingContract.owner(), _owner);
        assertEq(_vestingContract.totalAllocated(), 0);
        assertEq(_vestingContract.totalReleased(), 0);
        assertEq(_vestingContract.LOCK_PERIOD(), 365 days);
    }

    /* ============ Add Beneficiary ============ */

    function testAddBeneficiary() public {
        vm.warp(_token.GOVERNANCE_RELEASE_DEADLINE());
        vm.startPrank(_owner);
        _vestingContract.addBeneficiary(_user, 100, block.timestamp, 365 days);
        vm.stopPrank();
    }

    function testAddBeneficiary_RevertWhen_CallerIsNotOwner() public {
        vm.expectRevert("Ownable: caller is not the owner");
        _vestingContract.addBeneficiary(_user, 100, block.timestamp, 365 days);
    }

    function testAddBeneficiary_RevertWhen_BeneficiaryAlreadyExists() public {
        vm.startPrank(_owner);
        _vestingContract.addBeneficiary(_user, 100, block.timestamp, 365 days);
        vm.expectRevert("Beneficiary already exists");
        _vestingContract.addBeneficiary(_user, 100, block.timestamp, 365 days);
        vm.stopPrank();
    }

    function testAddBeneficiary_RevertWhen_DurationLessThanLockPeriod() public {
        vm.startPrank(_owner);
        vm.expectRevert("Vesting needs to at least be 1 year");
        _vestingContract.addBeneficiary(_user, 100, block.timestamp, 364 days);
        vm.stopPrank();
    }

    function testAddBeneficiary_RevertWhen_NotEnoughTokens() public {
        vm.startPrank(_owner);
        vm.expectRevert("Not enough tokens");
        _vestingContract.addBeneficiary(_user, 50_000_000e18 + 1, block.timestamp, 365 days);
        vm.stopPrank();
    }

    /* ============ Remove beneficiary tests ============ */

    function testRemoveBeneficiary() public {
        vm.startPrank(_owner);
        _vestingContract.addBeneficiary(_user, 100, block.timestamp, 365 days);
        vm.stopPrank();
        vm.startPrank(_owner);
        _vestingContract.removeBeneficiary(_user);
        vm.stopPrank();
    }

    function testRemoveBeneficiary_RevertWhen_BeneficiaryHasReleasedTokens() public {
        vm.startPrank(_owner);
        _vestingContract.addBeneficiary(_user, 100, block.timestamp, 365 days);
        vm.stopPrank();
        vm.warp(block.timestamp + 365 days + 1);
        vm.startPrank(_user);
        _vestingContract.release();
        vm.stopPrank();
        vm.startPrank(_owner);
        vm.expectRevert("Cannot remove beneficiary with released tokens");
        _vestingContract.removeBeneficiary(_user);
        vm.stopPrank();
    }

    function testRemoveBeneficiary_RevertWhen_CallerIsNotOwner() public {
        vm.startPrank(_owner);
        _vestingContract.addBeneficiary(_user, 100, block.timestamp, 365 days);
        vm.stopPrank();
        vm.expectRevert("Ownable: caller is not the owner");
        _vestingContract.removeBeneficiary(_user);
    }

    /* ============ Getter tests ============ */

    function testGetters() public {
        vm.startPrank(_owner);
        _vestingContract.addBeneficiary(_user, 100, block.timestamp, 365 days * 2);
        vm.stopPrank();
        assertEq(_vestingContract.grant(_user), 100);
        assertEq(_vestingContract.start(_user), block.timestamp);
        assertEq(_vestingContract.duration(_user), 365 days * 2);
        assertEq(_vestingContract.released(_user), 0);
        assertEq(_vestingContract.releasable(_user), 0);
        assertEq(_vestingContract.vestedAmount(_user, block.timestamp + 365 days), 50);
    }

    /* ============ Release tests ============ */

    function testRelease() public {
        vm.startPrank(_owner);
        _vestingContract.addBeneficiary(_user, 100, block.timestamp, 4 * 365 days);
        vm.stopPrank();
        vm.warp(block.timestamp + 4 * 365 days + 1);
        vm.startPrank(_user);
        _vestingContract.release();
        vm.stopPrank();
        assertEq(_token.balanceOf(_user), 100);
        assertEq(_vestingContract.totalReleased(), 100);
        assertEq(_vestingContract.released(_user), 100);
        assertEq(_vestingContract.releasable(_user), 0);
    }

    function testRelease_25Percent() public {
        vm.startPrank(_owner);
        _vestingContract.addBeneficiary(_user, 100, block.timestamp, 4 * 365 days);
        vm.stopPrank();
        vm.warp(block.timestamp + 365 days);
        vm.startPrank(_user);
        assertEq(_vestingContract.releasable(_user), 25);
        assertEq(_vestingContract.vestedAmount(_user, block.timestamp), 25);
        _vestingContract.release();
        vm.stopPrank();
        assertEq(_token.balanceOf(_user), 25);
        assertEq(_vestingContract.totalReleased(), 25);
        assertEq(_vestingContract.released(_user), 25);
        assertEq(_vestingContract.releasable(_user), 0);
    }

    function testRelease_100Percent() public {
        vm.startPrank(_owner);
        _vestingContract.addBeneficiary(_user, 100, block.timestamp, 365 days);
        vm.stopPrank();
        vm.warp(block.timestamp + 365 days + 1);
        vm.startPrank(_user);
        _vestingContract.release();
        vm.stopPrank();
        assertEq(_token.balanceOf(_user), 100);
        assertEq(_vestingContract.totalReleased(), 100);
        assertEq(_vestingContract.released(_user), 100);
        assertEq(_vestingContract.releasable(_user), 0);
    }

    function testRelease_RevertWhen_TokensAlreadyReleased() public {
        vm.startPrank(_owner);
        _vestingContract.addBeneficiary(_user, 100, block.timestamp, 365 days);
        vm.stopPrank();
        vm.warp(block.timestamp + 365 days + 1);
        vm.startPrank(_user);
        _vestingContract.release();
        vm.stopPrank();
        vm.expectRevert("Nothing to release");
        _vestingContract.release();
    }

    /* ============ Emergency distribution tests ============ */

    function testEmergencyDistribution() public {
        vm.startPrank(_owner);
        _vestingContract.addBeneficiary(_user, 100, block.timestamp, 365 days);
        vm.stopPrank();
        vm.warp(block.timestamp + 365 days + 1);
        vm.startPrank(_owner);
        _vestingContract.emergencyDistribution(_user, _user);
        vm.stopPrank();
        assertEq(_token.balanceOf(_user), 100);
        assertEq(_vestingContract.totalReleased(), 100);
        assertEq(_vestingContract.released(_user), 100);
        assertEq(_vestingContract.releasable(_user), 0);
    }

    function testEmergencyDistribution_RevertWhen_CallerIsNotOwner() public {
        vm.startPrank(_owner);
        _vestingContract.addBeneficiary(_user, 100, block.timestamp, 365 days);
        vm.stopPrank();
        vm.warp(block.timestamp + 365 days + 1);
        vm.expectRevert("Ownable: caller is not the owner");
        _vestingContract.emergencyDistribution(_user, _user);
    }
}
