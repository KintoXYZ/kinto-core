// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import "@kinto-core-test/SharedSetup.t.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import {BridgedKinto} from "@kinto-core/tokens/bridged/BridgedKinto.sol";

contract InsuranceWalletTest is SharedSetup {
    function setUp() public override {
        super.setUp();

        address admin = createUser("admin");
        address minter = createUser("minter");
        address upgrader = createUser("upgrader");

        vm.etch(KINTO_TOKEN, address(new BridgedKinto()).code);
        BridgedKinto token = BridgedKinto(KINTO_TOKEN);
        token.initialize("KINTO TOKEN", "KINTO", admin, minter, upgrader);

        vm.prank(minter);
        token.mint(address(_kintoWallet), 10e18);
    }

    function testSetInsurancePolicy() public {
        vm.prank(address(_kintoWallet));
        _kintoWallet.setInsurancePolicy(1, KINTO_TOKEN);

        assertEq(IERC20(KINTO_TOKEN).balanceOf(address(_kintoWallet)), 0);
    }
}
