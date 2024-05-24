// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "@kinto-core/tokens/KintoToken.sol";
import "@kinto-core/tokens/VestingContract.sol";

import "@kinto-core-test/helpers/Create2Helper.sol";

contract VestingContractTest is Test, Create2Helper {
    KintoToken _token;
    VestingContract _vestingContract;

    uint256 _ownerPk = 2;
    address payable _owner = payable(vm.addr(_ownerPk));

    uint256 _userPk = 3;
    address payable _user = payable(vm.addr(_userPk));

    uint256 _user2Pk = 4;
    address payable _user2 = payable(vm.addr(_user2Pk));

    function setUp() public {
        vm.startPrank(_owner);
        _token = new KintoToken();
        _vestingContract = new VestingContract(address(_token));
        _token.setVestingContract(address(_vestingContract));
        _token.transfer(address(_vestingContract), _token.SEED_TOKENS());
        vm.stopPrank();
    }

    function testUp() public view {
        assertEq(_token.balanceOf(address(_vestingContract)), _token.SEED_TOKENS());
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
        assertEq(_vestingContract.totalAllocated(), 100);
        vm.stopPrank();
    }

    function testAddBeneficiary_RevertWhen_CallerIsNotOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        _vestingContract.addBeneficiary(_user, 100, block.timestamp, 365 days);
    }

    function testAddBeneficiary_RevertWhen_BeneficiaryAlreadyExists() public {
        vm.startPrank(_owner);
        _vestingContract.addBeneficiary(_user, 100, block.timestamp, 365 days);
        vm.expectRevert(VestingContract.BeneficiaryAlreadyExists.selector);
        _vestingContract.addBeneficiary(_user, 100, block.timestamp, 365 days);
        vm.stopPrank();
    }

    function testAddBeneficiary_RevertWhen_DurationLessThanLockPeriod() public {
        vm.startPrank(_owner);
        vm.expectRevert(VestingContract.InLockPeriod.selector);
        _vestingContract.addBeneficiary(_user, 100, block.timestamp, 364 days);
        vm.stopPrank();
    }

    function testAddBeneficiary_RevertWhen_NotEnoughTokens() public {
        vm.startPrank(_owner);
        vm.expectRevert(VestingContract.NotEnoughTokens.selector);
        _vestingContract.addBeneficiary(_user, 50_000_000e18 + 1, block.timestamp, 365 days);
        vm.stopPrank();
    }

    /* ============ Adding many beneficary tests ============ */

    function testAddBeneficiaries() public {
        vm.warp(_token.GOVERNANCE_RELEASE_DEADLINE());
        vm.startPrank(_owner);
        address[] memory beneficiaries = new address[](2);
        beneficiaries[0] = _user;
        beneficiaries[1] = _user2;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 100;
        amounts[1] = 100;
        uint256[] memory starts = new uint256[](2);
        starts[0] = block.timestamp;
        starts[1] = block.timestamp;
        uint256[] memory durations = new uint256[](2);
        durations[0] = 365 days;
        durations[1] = 365 days;
        _vestingContract.addBeneficiaries(beneficiaries, amounts, starts, durations);

        assertEq(_vestingContract.totalAllocated(), 200);
        assertEq(_vestingContract.grant(_user), 100);
        assertEq(_vestingContract.grant(_user2), 100);
        assertEq(_vestingContract.start(_user), block.timestamp);
        assertEq(_vestingContract.start(_user2), block.timestamp);
        assertEq(_vestingContract.duration(_user), 365 days);
        assertEq(_vestingContract.duration(_user2), 365 days);
        vm.stopPrank();
    }

    function testAddBeneficiaries_RevertWhen_CallerIsNotOwner() public {
        address[] memory beneficiaries = new address[](2);
        beneficiaries[0] = _user;
        beneficiaries[1] = _user2;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 100;
        amounts[1] = 100;
        uint256[] memory starts = new uint256[](2);
        starts[0] = block.timestamp;
        starts[1] = block.timestamp;
        uint256[] memory durations = new uint256[](2);
        durations[0] = 365 days;
        durations[1] = 365 days;
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        _vestingContract.addBeneficiaries(beneficiaries, amounts, starts, durations);
    }

    function testAddBeneficiaries_RevertWhen_ArraysMismatch() public {
        vm.startPrank(_owner);
        address[] memory beneficiaries = new address[](2);
        beneficiaries[0] = _user;
        beneficiaries[1] = _user2;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 100;
        amounts[1] = 100;
        uint256[] memory starts = new uint256[](2);
        starts[0] = block.timestamp;
        starts[1] = block.timestamp;
        uint256[] memory durations = new uint256[](1);
        durations[0] = 365 days;
        vm.expectRevert(VestingContract.ArrayLengthMistmatch.selector);
        _vestingContract.addBeneficiaries(beneficiaries, amounts, starts, durations);
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
        vm.expectRevert(VestingContract.CantRemoveBeneficiary.selector);
        _vestingContract.removeBeneficiary(_user);
        vm.stopPrank();
    }

    function testRemoveBeneficiary_RevertWhen_CallerIsNotOwner() public {
        vm.startPrank(_owner);
        _vestingContract.addBeneficiary(_user, 100, block.timestamp, 365 days);
        vm.stopPrank();
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        _vestingContract.removeBeneficiary(_user);
    }

    function testEarlyLeave() public {
        vm.startPrank(_owner);
        _vestingContract.addBeneficiary(_user, 100, block.timestamp, 365 days * 2);
        vm.stopPrank();
        vm.warp(block.timestamp + 365 days);
        vm.startPrank(_owner);
        _vestingContract.earlyLeave(_user);
        vm.stopPrank();
        vm.startPrank(_user);
        _vestingContract.release();
        assertEq(_token.balanceOf(_user), 50);
        // check getters
        assertEq(_vestingContract.grant(_user), 50);
        assertEq(_vestingContract.start(_user), block.timestamp - 365 days);
        assertEq(_vestingContract.duration(_user), 365 days);
        assertEq(_vestingContract.released(_user), 50);
        assertEq(_vestingContract.releasable(_user), 0);
        assertEq(_vestingContract.vestedAmount(_user, block.timestamp + 365 days), 50);
        assertEq(_vestingContract.totalReleased(), 50);
        vm.stopPrank();
    }

    function testEarlyLeave_RevertWhen_PeriodIsOver() public {
        vm.startPrank(_owner);
        _vestingContract.addBeneficiary(_user, 100, block.timestamp, 365 days);
        vm.stopPrank();
        vm.warp(block.timestamp + 365 days + 1);
        vm.startPrank(_owner);
        vm.expectRevert(VestingContract.GrantPeriodEnded.selector);
        _vestingContract.earlyLeave(_user);
        vm.stopPrank();
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
        vm.expectRevert(VestingContract.NothingToRelease.selector);
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
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        _vestingContract.emergencyDistribution(_user, _user);
    }
}
