// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {BridgedWusdm} from "@kinto-core/tokens/bridged/BridgedWUSDM.sol";
import {UUPSProxy} from "@kinto-core-test/helpers/UUPSProxy.sol";
import "@kinto-core-test/SharedSetup.t.sol";

contract BridgedWusdmTest is SharedSetup {
    address minter;
    address upgrader;

    BridgedWusdm internal token;

    function setUp() public override {
        super.setUp();

        minter = createUser("minter");
        upgrader = createUser("upgrader");

        token = BridgedWusdm(
            payable(
                address(new UUPSProxy(address(new BridgedWusdm(18, address(_walletFactory), address(_kintoID))), ""))
            )
        );
        token.initialize("Wrapped USDM", "WUSDM", admin, minter, upgrader);
    }

    function setUpChain() public virtual override {
        setUpKintoLocal();
    }

    function testUp() public override {
        super.testUp();

        token = BridgedWusdm(
            payable(
                address(new UUPSProxy(address(new BridgedWusdm(18, address(_walletFactory), address(_kintoID))), ""))
            )
        );
        token.initialize("Wrapped USDM", "WUSDM", admin, minter, upgrader);

        assertEq(token.totalSupply(), 0);
        assertEq(token.name(), "Wrapped USDM");
        assertEq(token.symbol(), "WUSDM");
        assertTrue(token.hasRole(token.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(token.hasRole(token.MINTER_ROLE(), minter));
        assertTrue(token.hasRole(token.UPGRADER_ROLE(), upgrader));
    }

    function testMint_WhenDestinationIsEOA() public {
        vm.prank(minter);
        token.mint(_user, 1000);
        assertEq(token.balanceOf(_user), 1000);
    }

    function testMint_WhenDestinationIsContract() public {
        vm.prank(minter);
        token.mint(address(_kintoAppRegistry), 1000);
        assertEq(token.balanceOf(address(_kintoAppRegistry)), 1000);
    }

    function testMint_WhenDestinationIsKintoWallet_WhenHasNonUSATrait() public {
        vm.prank(minter);
        token.mint(address(_kintoWallet), 1000);
        assertEq(token.balanceOf(address(_kintoWallet)), 1000);
    }

    function testMint_RevertWhenDestinationIsKintoWallet_WhenHasUSATrait() public {
        vm.prank(_kycProvider);
        _kintoID.addTrait(_owner, 840);

        vm.expectRevert(
            abi.encodeWithSignature(
                "CountryIsNotAllowed(address,address,uint256)", address(0), address(_kintoWallet), 840
            )
        );
        vm.prank(minter);
        token.mint(address(_kintoWallet), 1000);
    }

    function testTransfer_WhenDestinationIsEOA() public {
        vm.prank(minter);
        token.mint(_user, 1000);

        vm.prank(_user);
        token.transfer(_owner, 500);

        assertEq(token.balanceOf(_user), 500);
    }

    function testTransfer_WhenDestinationIsContract() public {
        vm.prank(minter);
        token.mint(_user, 1000);

        vm.prank(_user);
        token.transfer(address(_kintoAppRegistry), 500);

        assertEq(token.balanceOf(address(_kintoAppRegistry)), 500);
    }

    function testTransfer_WhenDestinationIsKintoWallet_WhenHasNonUSATrait() public {
        vm.prank(minter);
        token.mint(_user, 1000);

        vm.prank(_user);
        token.transfer(address(_kintoWallet), 500);

        assertEq(token.balanceOf(address(_kintoWallet)), 500);
    }

    function testTransfer_RevertWhenDestinationIsKintoWallet_WhenHasUSATrait() public {
        vm.prank(_kycProvider);
        _kintoID.addTrait(_owner, 840);

        vm.prank(minter);
        token.mint(_user, 1000);

        vm.expectRevert(
            abi.encodeWithSignature(
                "CountryIsNotAllowed(address,address,uint256)", address(_user), address(_kintoWallet), 840
            )
        );
        vm.prank(_user);
        token.transfer(address(_kintoWallet), 500);
    }
}
