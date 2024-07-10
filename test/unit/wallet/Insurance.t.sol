// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import "@kinto-core-test/SharedSetup.t.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import {BridgedKinto} from "@kinto-core/tokens/bridged/BridgedKinto.sol";

contract InsuranceWalletTest is SharedSetup {
    address internal constant KINTO_TOKEN = 0x010700808D59d2bb92257fCafACfe8e5bFF7aB87;
    address internal constant TREASURY = 0x793500709506652Fcc61F0d2D0fDa605638D4293;

    function setUp() public override {
        super.setUp();

        address admin = createUser("admin");
        address minter = createUser("minter");
        address upgrader = createUser("upgrader");

        BridgedKinto token = BridgedKinto(payable(address(new UUPSProxy(address(new BridgedKinto()), ""))));
        token.initialize("KINTO TOKEN", "KINTO", admin, minter, upgrader);

        vm.prank(minter);
        token.mint(address(_kintoWallet), 80);

        vm.etch(KINTO_TOKEN, address(token).code);
    }

    function testSetInsurancePolicy() public {
        vm.skip(true);
        vm.prank(address(_kintoWallet));
        _kintoWallet.setInsurancePolicy(1, KINTO_TOKEN);

        assertEq(IERC20(KINTO_TOKEN).balanceOf(address(_kintoWallet)), 0);
    }
}
