// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "@aa/interfaces/IEntryPoint.sol";
import "@aa/core/EntryPoint.sol";

import "../src/paymasters/SponsorPaymaster.sol";

import "./helpers/KYCSignature.sol";
import "./helpers/UUPSProxy.sol";

contract SponsorPaymasterV999 is SponsorPaymaster {
    constructor(IEntryPoint __entryPoint, address _owner) SponsorPaymaster(__entryPoint) {
        _disableInitializers();
        _transferOwnership(_owner);
    }

    function newFunction() public pure returns (uint256) {
        return 1;
    }
}

contract SponsorPaymasterTest is KYCSignature {
    using ECDSAUpgradeable for bytes32;
    using SignatureChecker for address;

    EntryPoint _entryPoint;
    SponsorPaymaster _paymaster;
    SponsorPaymasterV999 _paymasterv999;
    UUPSProxy _proxy;

    address _owner = address(1);
    address _user = vm.addr(3);
    address _user2 = address(4);
    address _upgrader = address(5);

    function setUp() public {
        vm.chainId(1);
        vm.startPrank(_owner);
        // deploy the paymaster
        _entryPoint = new EntryPoint{salt: 0}();
        _paymaster = new SponsorPaymaster(_entryPoint);
        // deploy _proxy contract and point it to _implementation
        _proxy = new UUPSProxy(address(_paymaster), "");
        // wrap in ABI to support easier calls
        _paymaster = SponsorPaymaster(address(_proxy));
        // Initialize proxy
        _paymaster.initialize(_owner);
        vm.deal(_owner, 1e20);
        vm.deal(_user, 1e20);

        vm.stopPrank();
    }

    function testUp() public {
        assertEq(_paymaster.COST_OF_POST(), 60000);
    }

    // Upgrade Tests

    function testOwnerCanUpgrade() public {
        vm.startPrank(_owner);
        SponsorPaymasterV999 _newImplementation = new SponsorPaymasterV999(_entryPoint, _owner);
        _paymaster.upgradeTo(address(_newImplementation));
        // re-wrap the _proxy
        _paymasterv999 = SponsorPaymasterV999(address(_proxy));
        assertEq(_paymasterv999.newFunction(), 1);
        vm.stopPrank();
    }

    function testUpgrade_RevertWhen_CallerIsNotOwner() public {
        SponsorPaymasterV999 _newImplementation = new SponsorPaymasterV999(_entryPoint, _owner);
        vm.expectRevert("SP: not owner");
        _paymaster.upgradeTo(address(_newImplementation));
    }

    // Deposit & Stake
    function testOwnerCanDepositStakeAndWithdraw() public {
        vm.startPrank(_owner);
        uint256 balance = address(_owner).balance;
        _paymaster.addDepositFor{value: 5e18}(address(_owner));
        assertEq(address(_owner).balance, balance - 5e18);
        _paymaster.unlockTokenDeposit();
        vm.roll(block.timestamp + 1);
        _paymaster.withdrawTokensTo(address(_owner), 5e18);
        assertEq(address(_owner).balance, balance);
        vm.stopPrank();
    }

    function testUserCanDepositStakeAndWithdraw() public {
        vm.startPrank(_user);
        uint256 balance = address(_user).balance;
        _paymaster.addDepositFor{value: 5e18}(address(_user));
        assertEq(address(_user).balance, balance - 5e18);
        _paymaster.unlockTokenDeposit();
        // advance block to allow withdraw
        vm.roll(block.timestamp + 1);
        _paymaster.withdrawTokensTo(address(_user), 5e18);
        assertEq(address(_user).balance, balance);
        vm.stopPrank();
    }

    function test_RevertWhen_UserCanDepositStakeAndWithdrawWithoutRoll() public {
        // user deposits 5 eth
        uint256 balance = address(this).balance;
        _paymaster.addDepositFor{value: 5e18}(address(this));
        assertEq(address(this).balance, balance - 5e18);

        // user unlocks token deposit
        _paymaster.unlockTokenDeposit();

        // user withdraws 5 eth
        vm.expectRevert("SP: must unlockTokenDeposit");
        _paymaster.withdrawTokensTo(address(this), 5e18);

        assertEq(address(this).balance, balance - 5e18);
    }

    function testOwnerCanWithdrawAllInEmergency() public {
        vm.prank(_user);
        _paymaster.addDepositFor{value: 5e18}(address(_user));

        vm.startPrank(_owner);

        uint256 balance = address(_owner).balance;
        _paymaster.addDepositFor{value: 5e18}(address(_owner));

        _paymaster.withdrawTo(payable(_owner), address(_entryPoint).balance);
        assertEq(address(_paymaster).balance, 0);
        assertEq(address(_owner).balance, balance + 5e18);

        vm.stopPrank();
    }

    function test_RevertWhen_UserCanWithdrawAllInEmergency() public {
        vm.prank(_owner);
        _paymaster.addDepositFor{value: 5e18}(address(_owner));

        // user deposits 5 eth and then tries to withdraw all
        vm.startPrank(_user);
        _paymaster.addDepositFor{value: 5e18}(address(_user));
        vm.expectRevert("Ownable: caller is not the owner");
        _paymaster.withdrawTo(payable(_user), address(_entryPoint).balance);
        vm.stopPrank();
    }
}
