// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import '../src/tokens/EngenCredits.sol';
import 'forge-std/Test.sol';
import 'forge-std/console.sol';
import {UserOp} from './helpers/UserOp.sol';
import {UUPSProxy} from './helpers/UUPSProxy.sol';
import {AATestScaffolding} from './helpers/AATestScaffolding.sol';
import {Create2Helper} from './helpers/Create2Helper.sol';
import '@aa/core/EntryPoint.sol';


contract EngenCreditsV2 is EngenCredits {
    function newFunction() external pure returns (uint256) {
        return 1;
    }
    constructor() EngenCredits() {}
}

contract EngenCreditsTest is Create2Helper, UserOp, AATestScaffolding {
    EngenCreditsV2 _engenCreditsV2;

    uint256 _chainID = 1;

    address payable _owner = payable(vm.addr(1));
    address _user = vm.addr(3);
    address _user2 = vm.addr(4);
    address _kycProvider = address(6);
    address _recoverer = address(7);

    function setUp() public {
        vm.chainId(1);
        vm.startPrank(address(1));
        _owner.transfer(1e18);
        vm.stopPrank();
        deployAAScaffolding(_owner, _kycProvider, _recoverer);
        _setPaymasterForContract(address(_engenCredits));
        _setPaymasterForContract(address(_kintoWalletv1));

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
        vm.startPrank(_recoverer);
        EngenCreditsV2 _implementationV2 = new EngenCreditsV2();
        _engenCredits.upgradeTo(address(_implementationV2));
        // re-wrap the _proxy
        _engenCreditsV2 = EngenCreditsV2(address(_engenCredits));
        assertEq(_engenCreditsV2.newFunction(), 1);
        vm.stopPrank();
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
        vm.expectRevert('EC: Transfers not enabled');
        _engenCredits.transfer(_user2, 100);
        vm.stopPrank();
    }

    function testNobodyCanBurn() public {
        vm.startPrank(_owner);
        _engenCredits.mint(_user, 100);
        vm.expectRevert('EC: Transfers not enabled');
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

    /* ============ Engen Tests ============ */

    function testWalletCanGetPoints() public {
        assertEq(_engenCredits.balanceOf(address(_kintoWalletv1)), 0);
        assertEq(_engenCredits.calculatePoints(address(_kintoWalletv1)), 15);
        vm.startPrank(_owner);
        // Let's send a transaction to the counter contract through our wallet
        uint startingNonce = _kintoWalletv1.getNonce();
        uint256[] memory privateKeys = new uint256[](1);
        privateKeys[0] = 1;
        UserOperation memory userOp = this.createUserOperationWithPaymaster(
            _chainID,
            address(_kintoWalletv1), startingNonce + 1, privateKeys, address(_engenCredits), 0,
            abi.encodeWithSignature('mintCredits()'), address(_paymaster));
        UserOperation[] memory userOps = new UserOperation[](2);
        userOps[0] = createApprovalUserOp(
            _chainID,
            privateKeys,
            address(_kintoWalletv1),
            _kintoWalletv1.getNonce(),
            address(_engenCredits),
            address(_paymaster)
        );
        userOps[1] = userOp;
        // Execute the transaction via the entry point
        _entryPoint.handleOps(userOps, payable(_owner));
        assertEq(_engenCredits.balanceOf(address(_kintoWalletv1)), 15);
        vm.stopPrank();
    }

    function testWalletCanGetPointsWithOverride() public {
        vm.startPrank(_owner);
        uint256[] memory points = new uint256[](1);
        points[0] = 10;
        address[] memory addresses = new address[](1);
        addresses[0] = address(_kintoWalletv1);
        _engenCredits.setPhase1Override(addresses, points);
        assertEq(_engenCredits.balanceOf(address(_kintoWalletv1)), 0);
        assertEq(_engenCredits.calculatePoints(address(_kintoWalletv1)), 20);
        // Let's send a transaction to the counter contract through our wallet
        uint startingNonce = _kintoWalletv1.getNonce();
        uint256[] memory privateKeys = new uint256[](1);
        privateKeys[0] = 1;
        UserOperation memory userOp = this.createUserOperationWithPaymaster(
            _chainID,
            address(_kintoWalletv1), startingNonce + 1, privateKeys, address(_engenCredits), 0,
            abi.encodeWithSignature('mintCredits()'), address(_paymaster));
        UserOperation[] memory userOps = new UserOperation[](2);
        userOps[0] = createApprovalUserOp(
            _chainID,
            privateKeys,
            address(_kintoWalletv1),
            _kintoWalletv1.getNonce(),
            address(_engenCredits),
            address(_paymaster)
        );
        userOps[1] = userOp;
        // Execute the transaction via the entry point
        _entryPoint.handleOps(userOps, payable(_owner));
        assertEq(_engenCredits.balanceOf(address(_kintoWalletv1)), 20);
        vm.stopPrank();
    }

    function testWalletCannotGetPointsTwice() public {
        assertEq(_engenCredits.balanceOf(address(_kintoWalletv1)), 0);
        assertEq(_engenCredits.calculatePoints(address(_kintoWalletv1)), 15);
        vm.startPrank(_owner);
        // Let's send a transaction to the counter contract through our wallet
        uint startingNonce = _kintoWalletv1.getNonce();
        uint256[] memory privateKeys = new uint256[](1);
        privateKeys[0] = 1;
        UserOperation memory userOp = this.createUserOperationWithPaymaster(
            _chainID,
            address(_kintoWalletv1), startingNonce + 1, privateKeys, address(_engenCredits), 0,
            abi.encodeWithSignature('mintCredits()'), address(_paymaster));
        UserOperation[] memory userOps = new UserOperation[](2);
        userOps[0] = createApprovalUserOp(
            _chainID,
            privateKeys,
            address(_kintoWalletv1),
            _kintoWalletv1.getNonce(),
            address(_engenCredits),
            address(_paymaster)
        );
        userOps[1] = userOp;
        // Execute the transaction via the entry point
        _entryPoint.handleOps(userOps, payable(_owner));
        assertEq(_engenCredits.balanceOf(address(_kintoWalletv1)), 15);
        // call again
        userOp = this.createUserOperationWithPaymaster(
            _chainID,
            address(_kintoWalletv1), startingNonce + 2, privateKeys, address(_engenCredits), 0,
            abi.encodeWithSignature('mintCredits()'), address(_paymaster));
        userOps = new UserOperation[](1);
        userOps[0] = userOp;
        _entryPoint.handleOps(userOps, payable(_owner));
        assertEq(_engenCredits.balanceOf(address(_kintoWalletv1)), 15);
        vm.stopPrank();
    }

}
