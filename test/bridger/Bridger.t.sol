// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "@oz/contracts/utils/cryptography/ECDSA.sol";

import "../../src/interfaces/IBridger.sol";
import "../../src/bridger/Bridger.sol";
import "../helpers/UUPSProxy.sol";
import "../SharedSetup.t.sol";

contract BridgerNewUpgrade is Bridger {
    function newFunction() external pure returns (uint256) {
        return 1;
    }

    constructor() Bridger() {}
}

contract BridgerTest is SharedSetup {
    using ECDSA for bytes32;

    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant stETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address constant l1ToL2Router = 0xD9041DeCaDcBA88844b373e7053B4AC7A3390D60;
    Bridger _bridger;

    function testUp() public override {
        super.testUp();
        _bridger = new Bridger();
        assertEq(_bridger.depositCount(), 0);
    }

    /* ============ Upgrade tests ============ */

    function testUpgradeTo() public {
        BridgerNewUpgrade _newImpl = new BridgerNewUpgrade();
        vm.prank(_owner);
        _bridger.upgradeToAndCall(address(_newImpl), bytes(""));

        assertEq(BridgerNewUpgrade(payable(address(_bridger))).newFunction(), 1);
    }

    function testUpgradeTo_RevertWhen_CallerIsNotOwner() public {
        BridgerNewUpgrade _newImpl = new BridgerNewUpgrade();

        vm.expectRevert(IBridger.OnlyOwner.selector);
        if (fork) {
            Upgradeable(address(_bridger)).upgradeTo(address(_newImpl));
        } else {
            _bridger.upgradeToAndCall(address(_newImpl), bytes(""));
        }
    }

    /* ============ Bridger Deposit tests ============ */

    function testDeposit_WhenCallingOnBehalf() public {
        IBridger.SignatureData memory sigdata =
            _auxCreateBridgeSignature(_bridger, _user, USDC, 1000e6, stETH, _userPk, block.timestamp + 1000);

        vm.prank(_owner);
        _bridger.depositBySig(
            address(_kintoWallet), sigdata, IBridger.SwapData(address(1), address(1), bytes("")), bytes("")
        );
        assertEq(_bridger.nonces(_user), 1);
        assertEq(_bridger.deposits(_user, address(1)), 1);
    }

    function testDeposit_RevertWhen_CallerIsNotOwnerOrSender() public {
        vm.prank(_owner);
        IBridger.SignatureData memory sigdata =
            _auxCreateBridgeSignature(_bridger, _user, USDC, 1000e6, stETH, _userPk, block.timestamp + 1000);
        vm.expectRevert(IBridger.OnlySender.selector);
        _bridger.depositBySig(
            address(_kintoWallet), sigdata, IBridger.SwapData(address(1), address(1), bytes("")), bytes("")
        );
    }

    /* ============ Withdraw tests ============ */
}
