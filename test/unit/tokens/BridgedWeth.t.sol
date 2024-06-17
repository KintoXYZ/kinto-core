// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {IAccessControl} from "@openzeppelin-5.0.1/contracts/access/IAccessControl.sol";

import {BridgedWeth} from "@kinto-core/tokens/bridged/BridgedWeth.sol";
import {IWETH} from "@kinto-core/interfaces/IWETH.sol";
import {UUPSProxy} from "@kinto-core-test/helpers/UUPSProxy.sol";
import {BaseTest} from "@kinto-core-test/helpers/BaseTest.sol";
import {ReceiveRevert} from "@kinto-core-test/helpers/ReceiveRevert.sol";
import {BridgedTokenHarness} from "@kinto-core-test/harness/BridgedTokenHarness.sol";

contract BridgedWethTest is BaseTest {
    address admin;
    address minter;
    address upgrader;
    address alice;

    BridgedWeth internal token;
    ReceiveRevert internal receiveRevert;

    function setUp() public override {
        admin = createUser("admin");
        minter = createUser("minter");
        upgrader = createUser("upgrader");
        alice = createUser("alice");

        receiveRevert = new ReceiveRevert();

        token = BridgedWeth(payable(address(new UUPSProxy(address(new BridgedWeth(18)), ""))));
        token.initialize("wrapped eth", "ETH", admin, minter, upgrader);
    }

    function testUp() public view override {
        assertEq(token.totalSupply(), 0);
        assertEq(token.name(), "wrapped eth");
        assertEq(token.symbol(), "ETH");
        assertTrue(token.hasRole(token.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(token.hasRole(token.MINTER_ROLE(), minter));
        assertTrue(token.hasRole(token.UPGRADER_ROLE(), upgrader));
    }

    function testDeposit() public {
        uint256 depositAmount = 1 ether;
        vm.deal(alice, depositAmount);

        vm.prank(alice);
        token.deposit{value: depositAmount}();

        assertEq(token.balanceOf(alice), depositAmount);
        assertEq(address(token).balance, depositAmount);
    }

    function testWithdraw() public {
        uint256 depositAmount = 1 ether;
        uint256 withdrawAmount = 0.5 ether;
        vm.deal(alice, depositAmount);

        vm.prank(alice);
        token.deposit{value: depositAmount}();

        vm.prank(alice);
        token.withdraw(withdrawAmount);

        assertEq(token.balanceOf(alice), depositAmount - withdrawAmount);
        assertEq(address(token).balance, depositAmount - withdrawAmount);
        assertEq(alice.balance, withdrawAmount);
    }

    function testDepositTo() public {
        uint256 depositAmount = 1 ether;
        vm.deal(alice, depositAmount);

        vm.prank(alice);
        token.depositTo{value: depositAmount}(alice);

        assertEq(token.balanceOf(alice), depositAmount);
        assertEq(address(token).balance, depositAmount);
    }

    function testWithdrawTo() public {
        uint256 depositAmount = 1 ether;
        uint256 withdrawAmount = 0.5 ether;
        vm.deal(alice, depositAmount);

        vm.prank(alice);
        token.deposit{value: depositAmount}();

        vm.prank(alice);
        token.withdrawTo(alice, withdrawAmount);

        assertEq(token.balanceOf(alice), depositAmount - withdrawAmount);
        assertEq(address(token).balance, depositAmount - withdrawAmount);
        assertEq(alice.balance, withdrawAmount);
    }

    function testReceive() public {
        uint256 depositAmount = 1 ether;
        vm.deal(alice, depositAmount);

        vm.prank(alice);
        (bool success,) = address(token).call{value: depositAmount}("");

        assertTrue(success);
        assertEq(token.balanceOf(alice), depositAmount);
        assertEq(address(token).balance, depositAmount);
    }

    function testEthTransferFailed() public {
        uint256 depositAmount = 1 ether;
        uint256 withdrawAmount = 0.5 ether;
        vm.deal(alice, depositAmount);

        vm.prank(alice);
        token.deposit{value: depositAmount}();

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IWETH.EthTransferFailed.selector, address(receiveRevert), withdrawAmount)
        );
        token.withdrawTo(address(receiveRevert), withdrawAmount);
    }
}
