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

    constructor() BridgerL2() {}
}

contract BridgerL2Test is TestSignature, SharedSetup {


    function setUp() public override {
        super.setUp();
    }

    function testUp() public override {
        // super.testUp();
        assertEq(_bridger.depositCount(), 0);
        assertEq(_bridger.owner(), address(_owner));
        assertEq(_bridger.swapsEnabled(), false);
    }

    /* ============ Upgrade tests ============ */

    function testUpgradeTo() public {
        BridgerNewUpgrade _newImpl = new BridgerNewUpgrade();
        vm.prank(_owner);
        _bridger.upgradeTo(address(_newImpl));
        assertEq(BridgerNewUpgrade(payable(address(_bridger))).newFunction(), 1);
    }

    function testUpgradeTo_RevertWhen_CallerIsNotOwner() public {
        BridgerNewUpgrade _newImpl = new BridgerNewUpgrade();
        vm.expectRevert(IBridger.OnlyOwner.selector);
        _bridger.upgradeToAndCall(address(_newImpl), bytes(""));
    }

    /* ============ Bridger Deposit By Sig tests ============ */
}
