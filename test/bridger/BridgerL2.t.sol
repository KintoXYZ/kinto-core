// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../../src/interfaces/IBridger.sol";
import "../../src/bridger/BridgerL2.sol";

import "../helpers/UUPSProxy.sol";
import "../helpers/TestSignature.sol";
import "../helpers/TestSignature.sol";
import "../SharedSetup.t.sol";

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract BridgerL2NewUpgrade is BridgerL2 {
    function newFunction() external pure returns (uint256) {
        return 1;
    }

    constructor(address factory) BridgerL2(factory) {}
}

contract BridgerL2Test is TestSignature, SharedSetup {
    function setUp() public override {
        super.setUp();
        fundSponsorForApp(_owner, address(_bridgerL2));
        registerApp(_owner, "bridger", address(_bridgerL2));
    }

    function testUp() public override {
        assertEq(_bridgerL2.depositCount(), 0);
        assertEq(_bridgerL2.owner(), address(_owner));
        assertEq(_bridgerL2.unlocked(), false);
    }

    /* ============ Upgrade tests ============ */

    function testUpgradeTo() public {
        BridgerL2NewUpgrade _newImpl = new BridgerL2NewUpgrade(address(_walletFactory));
        vm.prank(_owner);
        _bridgerL2.upgradeTo(address(_newImpl));
        assertEq(BridgerL2NewUpgrade(payable(address(_bridgerL2))).newFunction(), 1);
    }

    function testUpgradeTo_RevertWhen_CallerIsNotOwner() public {
        BridgerL2NewUpgrade _newImpl = new BridgerL2NewUpgrade(address(_walletFactory));
        vm.expectRevert(IBridger.OnlyOwner.selector);
        _bridgerL2.upgradeToAndCall(address(_newImpl), bytes(""));
    }

    /* ============ Bridger Privileged Methods ============ */
}
