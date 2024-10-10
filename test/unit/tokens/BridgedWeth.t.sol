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
    address minter;
    address upgrader;

    BridgedWeth internal token;
    ReceiveRevert internal receiveRevert;

    function setUp() public override {
        super.setUp();

        minter = createUser("minter");
        upgrader = createUser("upgrader");

        receiveRevert = new ReceiveRevert();

        token = BridgedWeth(payable(address(new UUPSProxy(address(new BridgedWeth(18)), ""))));
        token.initialize("wrapped eth", "ETH", admin0, minter, upgrader);
    }

    function testUp() public view override {
        assertEq(token.totalSupply(), 0);
        assertEq(token.name(), "wrapped eth");
        assertEq(token.symbol(), "ETH");
        assertTrue(token.hasRole(token.DEFAULT_ADMIN_ROLE(), admin0));
        assertTrue(token.hasRole(token.MINTER_ROLE(), minter));
        assertTrue(token.hasRole(token.UPGRADER_ROLE(), upgrader));
    }

    function testDeposit() public {
        uint256 depositAmount = 1 ether;
        vm.deal(alice0, depositAmount);

        vm.prank(alice0);
        token.deposit{value: depositAmount}();

        assertEq(token.balanceOf(alice0), depositAmount);
        assertEq(address(token).balance, depositAmount);
    }

    function testWithdraw() public {
        uint256 depositAmount = 1 ether;
        uint256 withdrawAmount = 0.5 ether;
        vm.deal(alice0, depositAmount);

        vm.prank(alice0);
        token.deposit{value: depositAmount}();

        vm.prank(alice0);
        token.withdraw(withdrawAmount);

        assertEq(token.balanceOf(alice0), depositAmount - withdrawAmount);
        assertEq(address(token).balance, depositAmount - withdrawAmount);
        assertEq(alice0.balance, withdrawAmount);
    }

    function testDepositTo() public {
        uint256 depositAmount = 1 ether;
        vm.deal(alice0, depositAmount);

        vm.prank(alice0);
        token.depositTo{value: depositAmount}(alice0);

        assertEq(token.balanceOf(alice0), depositAmount);
        assertEq(address(token).balance, depositAmount);
    }

    function testWithdrawTo() public {
        uint256 depositAmount = 1 ether;
        uint256 withdrawAmount = 0.5 ether;
        vm.deal(alice0, depositAmount);

        vm.prank(alice0);
        token.deposit{value: depositAmount}();

        vm.prank(alice0);
        token.withdrawTo(alice0, withdrawAmount);

        assertEq(token.balanceOf(alice0), depositAmount - withdrawAmount);
        assertEq(address(token).balance, depositAmount - withdrawAmount);
        assertEq(alice0.balance, withdrawAmount);
    }

    function testReceive() public {
        uint256 depositAmount = 1 ether;
        vm.deal(alice0, depositAmount);

        vm.prank(alice0);
        (bool success,) = address(token).call{value: depositAmount}("");

        assertTrue(success);
        assertEq(token.balanceOf(alice0), depositAmount);
        assertEq(address(token).balance, depositAmount);
    }

    function testEthTransferFailed() public {
        uint256 depositAmount = 1 ether;
        uint256 withdrawAmount = 0.5 ether;
        vm.deal(alice0, depositAmount);

        vm.prank(alice0);
        token.deposit{value: depositAmount}();

        vm.prank(alice0);
        vm.expectRevert(
            abi.encodeWithSelector(IWETH.EthTransferFailed.selector, address(receiveRevert), withdrawAmount)
        );
        token.withdrawTo(address(receiveRevert), withdrawAmount);
    }
}
