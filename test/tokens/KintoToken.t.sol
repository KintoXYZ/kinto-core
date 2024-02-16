// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../../src/tokens/KintoToken.sol";
import "../../src/tokens/VestingContract.sol";
import "../../src/sample/Counter.sol";
import "../SharedSetup.t.sol";

contract KintoTokenTest is SharedSetup {
    KintoToken _token;

    function setUp() public override {
        super.setUp();
        vm.startPrank(_owner);
        _token = new KintoToken();
        vm.stopPrank();
    }

    function testUp() public override {
        super.testUp();
        assertEq(_token.totalSupply(), _token.SEED_TOKENS());
        assertEq(_token.owner(), _owner);
        assertEq(_token.name(), "Kinto Token");
        assertEq(_token.symbol(), "KINTO");
        assertEq(_token.balanceOf(_owner), _token.SEED_TOKENS());
    }

    /* ============ Token tests ============ */

    function testMintAfterDeadline() public {
        vm.warp(_token.GOVERNANCE_RELEASE_DEADLINE());
        vm.startPrank(_owner);
        _token.mint(_user, 100);
        vm.stopPrank();
    }

    function testMintLaunchSupplyAfterGovernance() public {
        vm.warp(_token.GOVERNANCE_RELEASE_DEADLINE());
        vm.startPrank(_owner);
        _token.mint(_user, _token.MAX_SUPPLY_LAUNCH() - _token.totalSupply());
        vm.stopPrank();
    }

    function testMintInflationAfter2Years() public {
        vm.warp(_token.GOVERNANCE_RELEASE_DEADLINE() + 2 * 365 days);
        vm.startPrank(_owner);
        _token.mint(_user, _token.MAX_SUPPLY_LAUNCH() + 1_000_000e18 - _token.totalSupply());
        vm.stopPrank();
    }

    function testMintInflationAfter10Years() public {
        vm.warp(_token.GOVERNANCE_RELEASE_DEADLINE() + 10 * 365 days);
        vm.startPrank(_owner);
        _token.mint(_user, _token.MAX_CAP_SUPPLY_EVER() - _token.totalSupply());
        vm.stopPrank();
    }

    function testMintInflationAfter10Years_RevertWhen_MoreThanMaxCap() public {
        vm.warp(_token.GOVERNANCE_RELEASE_DEADLINE() + 10 * 365 days);
        vm.startPrank(_owner);
        vm.expectRevert("Cannot exceed max supply");
        _token.mint(_user, 15_000_001e18);
        vm.stopPrank();
    }

    function testMint_RevertWhen_CallerMintMoreThanSupplyLaunch() public {
        vm.warp(_token.deployedAt() + 365 days);
        vm.startPrank(_owner);
        vm.expectRevert("Cannot exceed max supply");
        _token.mint(_user, 15_000_001e18);
        vm.stopPrank();
    }

    function testMint_RevertWhen_CallerIsOwnerBeforeDeadline() public {
        vm.startPrank(_owner);
        vm.expectRevert("Not transferred to governance yet");
        _token.mint(_user, 100);
        vm.stopPrank();
    }

    function testMint_RevertWhen_CallerIsNotOwner() public {
        vm.expectRevert("Ownable: caller is not the owner");
        _token.mint(_user, 100);
    }

    function testMint_RevertWhen_CallerIsNotOwnerAfterDeadline() public {
        vm.warp(_token.GOVERNANCE_RELEASE_DEADLINE());
        vm.expectRevert("Ownable: caller is not the owner");
        _token.mint(_user, 100);
    }

    function testTransfer_RevertWhen_CallerIsAnyone() public {
        vm.warp(_token.GOVERNANCE_RELEASE_DEADLINE());
        vm.startPrank(_owner);
        _token.mint(_owner, 100);
        vm.expectRevert("Kinto Tokens Transfers are disabled");
        _token.transfer(_user2, 100);
        vm.stopPrank();
    }

    /* ============ Burn tests ============ */

    function testBurn_RevertWhen_CallerIsAnyone() public {
        vm.startPrank(_owner);
        vm.expectRevert("Burn is not allowed");
        _token.burn(100);
        vm.stopPrank();
    }

    /* ============ Transfer tests ============ */

    function testTransferFrom_RevertWhen_CallerIsAnyoneAfterMint() public {
        vm.warp(_token.GOVERNANCE_RELEASE_DEADLINE());
        vm.startPrank(_owner);
        _token.mint(_owner, 100);
        vm.expectRevert("Kinto Tokens Transfers are disabled");
        _token.transfer(_user, 100);
        vm.stopPrank();
    }

    function testTransferToVestingContract() public {
        vm.warp(_token.GOVERNANCE_RELEASE_DEADLINE());
        vm.startPrank(_owner);
        address _vestingContract = address(new VestingContract(address(_token)));
        _token.setVestingContract(_vestingContract);
        _token.mint(_vestingContract, 100);
        vm.stopPrank();
    }

    function testTransferToMiningContract() public {
        vm.warp(_token.GOVERNANCE_RELEASE_DEADLINE());
        vm.startPrank(_owner);
        address _miningContract = address(new Counter());
        _token.setMiningContract(_miningContract);
        _token.mint(_miningContract, 100);
        vm.stopPrank();
    }

    function testEnableTokenTransfers_RevertWhen_CallerIsNotOwner() public {
        vm.expectRevert("Ownable: caller is not the owner");
        _token.enableTokenTransfers();
    }

    function testEnableTokenTransfers_RevertWhen_CallerIsOwnerBeforeDeadline() public {
        vm.startPrank(_owner);
        vm.expectRevert("Cannot enable transfers yet");
        _token.enableTokenTransfers();
        vm.stopPrank();
    }

    function testEnableTokenTransfers() public {
        vm.warp(_token.deployedAt() + 365 days);
        vm.startPrank(_owner);
        _token.enableTokenTransfers();
        vm.stopPrank();
    }

    function testTransferAfterEnabling() public {
        vm.warp(_token.deployedAt() + 365 days);
        vm.startPrank(_owner);
        _token.enableTokenTransfers();
        _token.transfer(_user, 100);
        assertEq(_token.balanceOf(_user), 100);
        vm.stopPrank();
    }

    /* ============ Setter tests ============ */

    function testSetVestingContract() public {
        vm.startPrank(_owner);
        address _vestingContract = address(new VestingContract(address(_token)));
        _token.setVestingContract(_vestingContract);
        vm.stopPrank();
    }

    function testSetVestingContract_RevertWhen_CallerIsNotOwner() public {
        vm.expectRevert("Ownable: caller is not the owner");
        _token.setVestingContract(address(1));
    }

    function testSetVestingContract_RevertWhen_InvalidAddress() public {
        vm.startPrank(_owner);
        vm.expectRevert("Invalid address");
        _token.setVestingContract(address(0));
        vm.stopPrank();
    }

    function testSetMiningContract() public {
        vm.startPrank(_owner);
        address _miningContract = address(new Counter());
        _token.setMiningContract(_miningContract);
        vm.stopPrank();
    }

    function testSetMiningContract_RevertWhen_CallerIsNotOwner() public {
        vm.expectRevert("Ownable: caller is not the owner");
        _token.setMiningContract(address(1));
    }

    function testSetMiningContract_RevertWhen_InvalidAddress() public {
        vm.startPrank(_owner);
        vm.expectRevert("Invalid address");
        _token.setMiningContract(address(0));
        vm.stopPrank();
    }
}
