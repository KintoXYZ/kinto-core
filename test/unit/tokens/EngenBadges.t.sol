// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import "@kinto-core/tokens/EngenBadges.sol";
import "@kinto-core-test/SharedSetup.t.sol";

contract EngenBadgesUpgrade is EngenBadges {
    function newFunction() external pure returns (uint256) {
        return 1;
    }
}

contract EngenBadgesTest is SharedSetup {
    string _uri = "https://api.example.com/metadata/";
    address alice;

    function setUp() public override {
        super.setUp();
        fundSponsorForApp(_owner, address(_engenBadges));
        fundSponsorForApp(_owner, address(_kintoWallet));

        registerApp(_owner, "engen badges", address(_engenBadges));
        alice = createUser("alice");

        whitelistApp(address(_engenBadges));

        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = _createUserOperation(
            address(_kintoWallet),
            address(_engenBadges),
            _kintoWallet.getNonce(),
            privateKeys,
            abi.encodeWithSignature("initialize(string)", _uri),
            address(_paymaster)
        );

        _entryPoint.handleOps(userOps, payable(_owner));
    }

    function testInitialization() public view {
        assertEq(_engenBadges.uri(1), _uri);
        assertTrue(_engenBadges.hasRole(_engenBadges.DEFAULT_ADMIN_ROLE(), address(_kintoWallet)));
        assertTrue(_engenBadges.hasRole(_engenBadges.MINTER_ROLE(), address(_kintoWallet)));
        assertTrue(_engenBadges.hasRole(_engenBadges.UPGRADER_ROLE(), address(_kintoWallet)));
    }

    function testMintBadges() public {
        uint256[] memory ids = new uint256[](2);
        ids[0] = 1;
        ids[1] = 2;

        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = _createUserOperation(
            address(_kintoWallet),
            address(_engenBadges),
            _kintoWallet.getNonce(),
            privateKeys,
            abi.encodeWithSignature("mintBadges(address,uint256[])", alice, ids),
            address(_paymaster)
        );

        _entryPoint.handleOps(userOps, payable(_owner));

        assertEq(_engenBadges.balanceOf(alice, 1), 1);
        assertEq(_engenBadges.balanceOf(alice, 2), 1);
    }

    function testMint_RevertWhen_NotMinter() public {
        uint256[] memory ids = new uint256[](2);
        ids[0] = 1;
        ids[1] = 2;

        bytes memory err = abi.encodePacked(
            "AccessControl: account ",
            Strings.toHexString(alice),
            " is missing role ",
            Strings.toHexString(uint256(_engenBadges.MINTER_ROLE()), 32)
        );

        vm.expectRevert(err);
        vm.prank(alice);
        _engenBadges.mintBadges(alice, ids);
    }

    function testMint_RevertWhen_NoIds() public {
        uint256[] memory ids = new uint256[](0);

        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = _createUserOperation(
            address(_kintoWallet),
            address(_engenBadges),
            _kintoWallet.getNonce(),
            privateKeys,
            abi.encodeWithSignature("mintBadges(address,uint256[])", alice, ids),
            address(_paymaster)
        );

        vm.recordLogs();
        _entryPoint.handleOps(userOps, payable(_owner));
        assertRevertReasonEq(EngenBadges.NoTokenIDsProvided.selector);
    }

    function testMintBatchRecipients() public {
        uint256 elements = 50;
        address[] memory recipients = new address[](elements);
        uint256[][] memory ids = new uint256[][](elements);

        for (uint256 i = 0; i < elements; i++) {
            recipients[i] = address(uint160(0xABCDE + i));
        }

        for (uint256 i = 0; i < elements; i++) {
            ids[i] = new uint256[](2);
            ids[i][0] = 1;
            ids[i][1] = 2;
        }

        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = _createUserOperation(
            address(_kintoWallet),
            address(_engenBadges),
            _kintoWallet.getNonce(),
            privateKeys,
            abi.encodeWithSignature("mintBadgesBatch(address[],uint256[][])", recipients, ids),
            address(_paymaster)
        );

        _entryPoint.handleOps(userOps, payable(_owner));

        for (uint256 i = 0; i < elements; i++) {
            assertEq(_engenBadges.balanceOf(recipients[i], 1), 1);
            assertEq(_engenBadges.balanceOf(recipients[i], 2), 1);
        }
    }

    function testMintBatchRecipients_RevertWhen_101addresses() public {
        uint256 elements = 101;
        address[] memory recipients = new address[](elements);
        uint256[][] memory ids = new uint256[][](elements);

        for (uint256 i = 0; i < elements; i++) {
            recipients[i] = address(uint160(0xABCDE + i));
        }

        for (uint256 i = 0; i < elements; i++) {
            ids[i] = new uint256[](2);
            ids[i][0] = 1;
            ids[i][1] = 2;
        }

        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = _createUserOperation(
            address(_kintoWallet),
            address(_engenBadges),
            _kintoWallet.getNonce(),
            privateKeys,
            abi.encodeWithSignature("mintBadgesBatch(address[],uint256[][])", recipients, ids),
            address(_paymaster)
        );

        vm.recordLogs();
        _entryPoint.handleOps(userOps, payable(_owner));
        assertRevertReasonEq(EngenBadges.MintToManyAddresses.selector);
    }

    function testMintBatchRecipients_RevertWhen_NoIds() public {
        uint256 elements = 0;
        address[] memory recipients = new address[](elements);
        uint256[][] memory ids = new uint256[][](elements);

        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = _createUserOperation(
            address(_kintoWallet),
            address(_engenBadges),
            _kintoWallet.getNonce(),
            privateKeys,
            abi.encodeWithSignature("mintBadgesBatch(address[],uint256[][])", recipients, ids),
            address(_paymaster)
        );

        vm.recordLogs();
        _entryPoint.handleOps(userOps, payable(_owner));
        assertRevertReasonEq(EngenBadges.NoTokenIDsProvided.selector);
    }

    function testMintBatchRecipients_RevertWhen_Missmatch() public {
        uint256 elements = 10;
        address[] memory recipients = new address[](elements);
        uint256[][] memory ids = new uint256[][](elements + 1);

        for (uint256 i = 0; i < elements; i++) {
            recipients[i] = address(uint160(0xABCDE + i));
        }

        for (uint256 i = 0; i < elements + 1; i++) {
            ids[i] = new uint256[](2);
            ids[i][0] = 1;
            ids[i][1] = 2;
        }

        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = _createUserOperation(
            address(_kintoWallet),
            address(_engenBadges),
            _kintoWallet.getNonce(),
            privateKeys,
            abi.encodeWithSignature("mintBadgesBatch(address[],uint256[][])", recipients, ids),
            address(_paymaster)
        );

        vm.recordLogs();
        _entryPoint.handleOps(userOps, payable(_owner));
        assertRevertReasonEq(EngenBadges.MismatchedInputLengths.selector);
    }

    function testUpgradeTo() public {
        EngenBadgesUpgrade newImpl = new EngenBadgesUpgrade();
        vm.prank(address(_kintoWallet));
        _engenBadges.upgradeTo(address(newImpl));

        EngenBadgesUpgrade _engenBadgeUpgrade = EngenBadgesUpgrade(address(_engenBadges));

        // new function is available
        assertEq(_engenBadgeUpgrade.newFunction(), 1);
        // old values are kept
        assertEq(_engenBadgeUpgrade.uri(1), _uri);
        assertTrue(_engenBadgeUpgrade.hasRole(_engenBadgeUpgrade.DEFAULT_ADMIN_ROLE(), address(_kintoWallet)));
        assertTrue(_engenBadgeUpgrade.hasRole(_engenBadgeUpgrade.MINTER_ROLE(), address(_kintoWallet)));
        assertTrue(_engenBadgeUpgrade.hasRole(_engenBadgeUpgrade.UPGRADER_ROLE(), address(_kintoWallet)));
    }

    function testUpgradeTo_RevertWhen_CallerIsNotUpgrader() public {
        EngenBadgesUpgrade newImpl = new EngenBadgesUpgrade();

        bytes memory err = abi.encodePacked(
            "AccessControl: account ",
            Strings.toHexString(alice),
            " is missing role ",
            Strings.toHexString(uint256(_engenBadges.UPGRADER_ROLE()), 32)
        );

        vm.prank(alice);
        vm.expectRevert(err);
        _engenBadges.upgradeTo(address(newImpl));
    }
}
