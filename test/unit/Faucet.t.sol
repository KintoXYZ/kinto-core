// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import "@kinto-core/interfaces/IFaucet.sol";
import "@kinto-core/Faucet.sol";

import "@kinto-core-test/helpers/UUPSProxy.sol";
import "@kinto-core-test/SharedSetup.t.sol";

contract FaucetNewUpgrade is Faucet {
    function newFunction() external pure returns (uint256) {
        return 1;
    }

    constructor(address _kintoWalletFactory) Faucet(_kintoWalletFactory) {}
}

contract FaucetTest is SharedSetup {
    using ECDSA for bytes32;

    function testUp() public override {
        super.testUp();
        assertEq(_faucet.CLAIM_AMOUNT(), 1 ether / 2000);
        assertEq(_faucet.FAUCET_AMOUNT(), 1 ether);
    }

    /* ============ Upgrade tests ============ */

    function testUpgradeTo() public {
        FaucetNewUpgrade _newImpl = new FaucetNewUpgrade(address(_walletFactory));
        vm.prank(_owner);
        _faucet.upgradeTo(address(_newImpl));

        assertEq(FaucetNewUpgrade(payable(address(_faucet))).newFunction(), 1);
    }

    function testUpgradeTo_RevertWhen_CallerIsNotOwner() public {
        FaucetNewUpgrade _newImpl = new FaucetNewUpgrade(address(_walletFactory));

        vm.expectRevert(IFaucet.OnlyOwner.selector);
        _faucet.upgradeTo(address(_newImpl));
    }

    /* ============ Start Faucet tests ============ */

    function testStartFaucet() public {
        uint256 previousBalance = address(_faucet).balance;
        vm.prank(_owner);
        _faucet.startFaucet{value: 1 ether}();
        assertEq(address(_faucet).balance, previousBalance + 1 ether);
    }

    function testStartFaucet_RevertWhen_AmountIsLess(uint256 amt) public {
        vm.deal(address(_faucet), 0);
        vm.assume(amt < _faucet.FAUCET_AMOUNT());
        vm.prank(_owner);
        vm.expectRevert(IFaucet.NotEnoughETH.selector);
        _faucet.startFaucet{value: amt}();
    }

    function testStartFaucet_RevertWhen_CallerIsNotOwner(address someone) public {
        vm.assume(someone != _faucet.owner());
        vm.deal(someone, 1 ether);
        vm.prank(someone);
        vm.expectRevert("Ownable: caller is not the owner");
        _faucet.startFaucet{value: 1 ether}();
    }

    /* ============ Claim From Faucet tests ============ */

    function testClaimFromFaucet_WhenCallingOnBehalf() public {
        IFaucet.SignatureData memory sigdata = _auxCreateSignature(_faucet, _user, _userPk, block.timestamp + 1000);

        vm.prank(_owner);
        _faucet.startFaucet{value: 1 ether}();
        assertEq(_faucet.claimed(_user), false);
        assertEq(_faucet.nonces(_user), 0);

        vm.prank(_owner);
        _walletFactory.claimFromFaucet(address(_faucet), sigdata);
        assertEq(_faucet.claimed(_user), true);
        assertEq(_faucet.nonces(_user), 1);
    }

    /* ============ Claim Kinto ETH tests ============ */

    function testClaimKintoETH() public {
        uint256 prevBalanceFaucet = address(_faucet).balance;
        uint256 prevBalanceUser = address(_user).balance;

        vm.prank(_owner);
        _faucet.startFaucet{value: 1 ether}();

        vm.prank(_user);
        _faucet.claimKintoETH();

        assertEq(address(_faucet).balance, prevBalanceFaucet + 1 ether - _faucet.CLAIM_AMOUNT());
        assertEq(address(_user).balance, prevBalanceUser + _faucet.CLAIM_AMOUNT());
    }

    function testClaimKintoETH_RevertWhen_ClaimTwice() public {
        vm.prank(_owner);
        _faucet.startFaucet{value: 1 ether}();

        vm.startPrank(_user);
        _faucet.claimKintoETH();

        vm.expectRevert(IFaucet.AlreadyClaimed.selector);
        _faucet.claimKintoETH();
        vm.stopPrank();
    }

    function testClaimKintoETH_RevertWhen_CallerIsNotFactory() public {
        vm.prank(_owner);
        _faucet.startFaucet{value: 1 ether}();

        IFaucet.SignatureData memory sigdata = _auxCreateSignature(_faucet, _user, _userPk, block.timestamp + 1000);
        vm.expectRevert(IFaucet.OnlyFactory.selector);
        _faucet.claimKintoETH(sigdata);
    }

    function testClaim_RevertWhen_FaucerIsNotActive() public {
        vm.prank(_owner);
        _faucet.withdrawAll();
        assertEq(_faucet.active(), false);

        vm.prank(_owner);
        vm.expectRevert(IFaucet.FaucetNotActive.selector);
        _faucet.claimKintoETH();
    }

    function testClaim_DeactivatesWhenNotEnoughBalanceForNextClaim() public {
        vm.prank(_owner);
        _faucet.startFaucet{value: 1 ether}();

        // reduce faucet balance to CLAIM AMOUNT
        vm.deal(address(_faucet), _faucet.CLAIM_AMOUNT());

        vm.prank(_user);
        _faucet.claimKintoETH();

        // assert faucet is deactivated
        assertEq(address(_faucet).balance, 0);
        assertEq(_faucet.active(), false);
    }

    /* ============ Withdraw tests ============ */

    function testWithdrawAll() public {
        uint256 previousBalance = address(_faucet).balance;

        vm.startPrank(_owner);

        _faucet.startFaucet{value: 1 ether}();
        assertEq(address(_faucet).balance, previousBalance + 1 ether);

        _faucet.withdrawAll();
        assertEq(address(_faucet).balance, 0);

        vm.stopPrank();
    }

    function testWithdrawAll_RevertWhen_CallerIsNotOwner() public {
        uint256 previousBalance = address(_faucet).balance;

        vm.prank(_owner);
        _faucet.startFaucet{value: 1 ether}();
        assertEq(address(_faucet).balance, previousBalance + 1 ether);

        vm.expectRevert("Ownable: caller is not the owner");
        _faucet.withdrawAll();
    }

    /* ============ Top up tests ============ */

    function testSendMoneyToAccount() public {
        uint256 balanceBefore = address(_faucet).balance;

        vm.prank(_owner);
        _walletFactory.sendMoneyToAccount{value: 1e15}(address(_faucet));

        assertEq(address(_faucet).balance, balanceBefore + 1e15);
    }
}
