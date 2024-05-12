// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import "@kinto-core/governance/EngenGovernance.sol";
import "@kinto-core/tokens/EngenCredits.sol";

import "@kinto-core-test/SharedSetup.t.sol";

contract EngenGovernanceTest is SharedSetup {
    function setUp() public override {
        super.setUp();
        fundSponsorForApp(_owner, address(_engenCredits));
        registerApp(_owner, "engen credits", address(_engenCredits));
    }

    function testUp() public override {
        super.testUp();
        assertEq(_engenCredits.totalSupply(), 0);
        assertEq(_engenCredits.owner(), _owner);
        assertEq(_engenCredits.transfersEnabled(), false);
        assertEq(_engenCredits.burnsEnabled(), false);
    }

    /* ============ Set Transfer Enabled tests ============ */


    /* ============ Set Burns Enabled tests ============ */


    /* ============ Mint Credits tests ============ */

    function testMintCredits() public {
        assertEq(_engenCredits.balanceOf(address(_kintoWallet)), 0);

        whitelistApp(address(_engenCredits));

        // set points
        uint256[] memory points = new uint256[](1);
        points[0] = 10;
        address[] memory addresses = new address[](1);
        addresses[0] = address(_kintoWallet);
        vm.prank(_owner);
        _engenCredits.setCredits(addresses, points);

        // mint credit
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = _createUserOperation(
            address(_kintoWallet),
            address(_engenCredits),
            _kintoWallet.getNonce(),
            privateKeys,
            abi.encodeWithSignature("mintCredits()"),
            address(_paymaster)
        );

        _entryPoint.handleOps(userOps, payable(_owner));
        assertEq(_engenCredits.balanceOf(address(_kintoWallet)), 10);
    }

}
