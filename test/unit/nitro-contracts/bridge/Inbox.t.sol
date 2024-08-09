// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";

import "@arbitrum/nitro-contracts/src/libraries/MessageTypes.sol";
import "@arbitrum/nitro-contracts/src/libraries/Error.sol";
import "@arbitrum/nitro-contracts/src/bridge/IOwnable.sol";
import "@arbitrum/nitro-contracts/src/bridge/IEthBridge.sol";
import {ERC20Bridge} from "@arbitrum/nitro-contracts/src/bridge/ERC20Bridge.sol";
import {ERC20Inbox} from "@arbitrum/nitro-contracts/src/bridge/ERC20Inbox.sol";
import {IInbox, IInboxBase} from "@arbitrum/nitro-contracts/src/bridge/IInbox.sol";
import {Bridge, IBridge} from "@arbitrum/nitro-contracts/src/bridge/Bridge.sol";
import {ISequencerInbox} from "@arbitrum/nitro-contracts/src/bridge/ISequencerInbox.sol";
import {AddressAliasHelper} from "@arbitrum/nitro-contracts/src/libraries/AddressAliasHelper.sol";

import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

import {Inbox} from "@kinto-core/nitro-contracts/bridge/Inbox.sol";
import {AbsInbox} from "@kinto-core/nitro-contracts/bridge/AbsInbox.sol";

contract Sender {}

library TestUtil {
    function deployProxy(address logic) public returns (address) {
        ProxyAdmin pa = new ProxyAdmin();
        return address(new TransparentUpgradeableProxy(address(logic), address(pa), ""));
    }
}

abstract contract AbsInboxTest is Test {
    IInboxBase public inbox;
    IBridge public bridge;

    uint256 public constant MAX_DATA_SIZE = 117_964;

    address public user = address(100);
    address public rollup = address(1000);
    address public seqInbox = address(1001);

    /* solhint-disable func-name-mixedcase */
    function test_getProxyAdmin() public {
        assertNotEq(inbox.getProxyAdmin(), address(0), "Invalid proxy admin");
    }

    function test_setAllowList() public {
        address[] memory users = new address[](2);
        users[0] = address(300);
        users[1] = address(301);

        bool[] memory allowed = new bool[](2);
        allowed[0] = true;
        allowed[0] = false;

        vm.expectEmit(true, true, true, true);
        emit AllowListAddressSet(users[0], allowed[0]);
        emit AllowListAddressSet(users[1], allowed[1]);

        vm.prank(rollup);
        inbox.setAllowList(users, allowed);

        assertEq(inbox.isAllowed(users[0]), allowed[0], "Invalid isAllowed user[0]");
        assertEq(inbox.isAllowed(users[1]), allowed[1], "Invalid isAllowed user[1]");
    }

    function test_setAllowList_revert_InvalidLength() public {
        address[] memory users = new address[](1);
        users[0] = address(300);

        bool[] memory allowed = new bool[](2);
        allowed[0] = true;
        allowed[0] = false;

        vm.expectRevert("INVALID_INPUT");
        vm.prank(rollup);
        inbox.setAllowList(users, allowed);
    }

    function test_setOutbox_revert_NonOwnerCall() public {
        // mock the owner() call on rollup
        address mockRollupOwner = address(10_000);
        vm.mockCall(rollup, abi.encodeWithSelector(IOwnable.owner.selector), abi.encode(mockRollupOwner));

        // setAllowList shall revert
        vm.expectRevert(abi.encodeWithSelector(NotRollupOrOwner.selector, address(this), rollup, mockRollupOwner));

        address[] memory users = new address[](2);
        users[0] = address(300);
        bool[] memory allowed = new bool[](2);
        allowed[0] = true;
        inbox.setAllowList(users, allowed);
    }

    function test_setAllowListEnabled_EnableAllowList() public {
        assertEq(inbox.allowListEnabled(), false, "Invalid initial value for allowList");

        vm.expectEmit(true, true, true, true);
        emit AllowListEnabledUpdated(true);

        vm.prank(rollup);
        inbox.setAllowListEnabled(true);

        assertEq(inbox.allowListEnabled(), true, "Invalid allowList");
    }

    function test_setAllowListEnabled_DisableAllowList() public {
        vm.prank(rollup);
        inbox.setAllowListEnabled(true);
        assertEq(inbox.allowListEnabled(), true, "Invalid initial value for allowList");

        vm.expectEmit(true, true, true, true);
        emit AllowListEnabledUpdated(false);

        vm.prank(rollup);
        inbox.setAllowListEnabled(false);

        assertEq(inbox.allowListEnabled(), false, "Invalid allowList");
    }

    function test_setAllowListEnabled_revert_AlreadyEnabled() public {
        vm.prank(rollup);
        inbox.setAllowListEnabled(true);
        assertEq(inbox.allowListEnabled(), true, "Invalid initial value for allowList");

        vm.expectRevert("ALREADY_SET");
        vm.prank(rollup);
        inbox.setAllowListEnabled(true);
    }

    function test_setAllowListEnabled_revert_AlreadyDisabled() public {
        vm.prank(rollup);
        vm.expectRevert("ALREADY_SET");
        inbox.setAllowListEnabled(false);
    }

    function test_setAllowListEnabled_revert_NonOwnerCall() public {
        // mock the owner() call on rollup
        address mockRollupOwner = address(10_000);
        vm.mockCall(rollup, abi.encodeWithSelector(IOwnable.owner.selector), abi.encode(mockRollupOwner));

        // setAllowListEnabled shall revert
        vm.expectRevert(abi.encodeWithSelector(NotRollupOrOwner.selector, address(this), rollup, mockRollupOwner));

        inbox.setAllowListEnabled(true);
    }

    function test_pause() public {
        assertEq((PausableUpgradeable(address(inbox))).paused(), false, "Invalid initial paused state");

        vm.prank(rollup);
        inbox.pause();

        assertEq((PausableUpgradeable(address(inbox))).paused(), true, "Invalid paused state");
    }

    function test_unpause() public {
        vm.prank(rollup);
        inbox.pause();
        assertEq((PausableUpgradeable(address(inbox))).paused(), true, "Invalid initial paused state");
        vm.prank(rollup);
        inbox.unpause();

        assertEq((PausableUpgradeable(address(inbox))).paused(), false, "Invalid paused state");
    }

    function test_initialize_revert_ReInit() public {
        vm.expectRevert("Initializable: contract is already initialized");
        inbox.initialize(bridge, ISequencerInbox(seqInbox));
    }

    function test_initialize_revert_NonDelegated() public {
        ERC20Inbox inb = new ERC20Inbox(MAX_DATA_SIZE);
        vm.expectRevert("Function must be called through delegatecall");
        inb.initialize(bridge, ISequencerInbox(seqInbox));
    }

    function test_sendL2MessageFromOrigin() public {
        // L2 msg params
        bytes memory data = abi.encodePacked("some msg");

        // expect event
        vm.expectEmit(true, true, true, true);
        emit InboxMessageDeliveredFromOrigin(0);

        // send L2 msg -> tx.origin == msg.sender
        vm.prank(user, user);
        uint256 msgNum = inbox.sendL2MessageFromOrigin(data);

        //// checks
        assertEq(msgNum, 0, "Invalid msgNum");
        assertEq(bridge.delayedMessageCount(), 1, "Invalid delayed message count");
    }

    function test_sendL2MessageFromOrigin_revert_WhenPaused() public {
        vm.prank(rollup);
        inbox.pause();

        vm.expectRevert("Pausable: paused");
        vm.prank(user);
        inbox.sendL2MessageFromOrigin(abi.encodePacked("some msg"));
    }

    function test_sendL2MessageFromOrigin_revert_NotAllowed() public {
        vm.prank(rollup);
        inbox.setAllowListEnabled(true);

        vm.expectRevert(abi.encodeWithSelector(NotAllowedOrigin.selector, user));
        vm.prank(user, user);
        inbox.sendL2MessageFromOrigin(abi.encodePacked("some msg"));
    }

    function test_sendL2MessageFromOrigin_revert_L1Forked() public {
        vm.chainId(10);
        vm.expectRevert(abi.encodeWithSelector(L1Forked.selector));
        vm.prank(user, user);
        inbox.sendL2MessageFromOrigin(abi.encodePacked("some msg"));
    }

    function test_sendL2MessageFromOrigin_revert_NotOrigin() public {
        vm.expectRevert(abi.encodeWithSelector(NotOrigin.selector));
        inbox.sendL2MessageFromOrigin(abi.encodePacked("some msg"));
    }

    function test_sendL2Message() public {
        // L2 msg params
        bytes memory data = abi.encodePacked("some msg");

        // expect event
        vm.expectEmit(true, true, true, true);
        emit InboxMessageDelivered(0, data);

        // send L2 msg -> tx.origin == msg.sender
        vm.prank(user, user);
        uint256 msgNum = inbox.sendL2Message(data);

        //// checks
        assertEq(msgNum, 0, "Invalid msgNum");
        assertEq(bridge.delayedMessageCount(), 1, "Invalid delayed message count");
    }

    function test_sendL2Message_revert_WhenPaused() public {
        vm.prank(rollup);
        inbox.pause();

        vm.expectRevert("Pausable: paused");
        vm.prank(user);
        inbox.sendL2Message(abi.encodePacked("some msg"));
    }

    function test_sendL2Message_revert_NotAllowed() public {
        vm.prank(rollup);
        inbox.setAllowListEnabled(true);

        vm.expectRevert(abi.encodeWithSelector(NotAllowedOrigin.selector, user));
        vm.prank(user, user);
        inbox.sendL2Message(abi.encodePacked("some msg"));
    }

    function test_sendL2Message_revert_L1Forked() public {
        vm.chainId(10);
        vm.expectRevert(abi.encodeWithSelector(L1Forked.selector));
        vm.prank(user, user);
        inbox.sendL2Message(abi.encodePacked("some msg"));
    }

    function test_sendUnsignedTransaction() public {
        // L2 msg params
        uint256 maxFeePerGas = 0;
        uint256 gasLimit = 10;
        uint256 nonce = 3;
        uint256 value = 300;
        bytes memory data = abi.encodePacked("test data");

        // expect event
        vm.expectEmit(true, true, true, true);
        emit InboxMessageDelivered(
            0,
            abi.encodePacked(
                L2MessageType_unsignedEOATx, gasLimit, maxFeePerGas, nonce, uint256(uint160(user)), value, data
            )
        );

        // send TX
        vm.prank(user, user);
        uint256 msgNum = inbox.sendUnsignedTransaction(gasLimit, maxFeePerGas, nonce, user, value, data);

        //// checks
        assertEq(msgNum, 0, "Invalid msgNum");
        assertEq(bridge.delayedMessageCount(), 1, "Invalid delayed message count");
    }

    function test_sendUnsignedTransaction_revert_WhenPaused() public {
        vm.prank(rollup);
        inbox.pause();

        vm.expectRevert("Pausable: paused");
        vm.prank(user);
        inbox.sendUnsignedTransaction(10, 10, 10, user, 10, abi.encodePacked("test data"));
    }

    function test_sendUnsignedTransaction_revert_NotAllowed() public {
        vm.prank(rollup);
        inbox.setAllowListEnabled(true);

        vm.expectRevert(abi.encodeWithSelector(NotAllowedOrigin.selector, user));
        vm.prank(user, user);
        inbox.sendUnsignedTransaction(10, 10, 10, user, 10, abi.encodePacked("test data"));
    }

    function test_sendUnsignedTransaction_revert_GasLimitTooLarge() public {
        uint256 tooBigGasLimit = uint256(type(uint64).max) + 1;

        vm.expectRevert(GasLimitTooLarge.selector);
        vm.prank(user, user);
        inbox.sendUnsignedTransaction(tooBigGasLimit, 10, 10, user, 10, abi.encodePacked("data"));
    }

    function test_sendContractTransaction() public {
        // L2 msg params
        uint256 maxFeePerGas = 0;
        uint256 gasLimit = 10;
        uint256 value = 300;
        bytes memory data = abi.encodePacked("test data");

        // expect event
        vm.expectEmit(true, true, true, true);
        emit InboxMessageDelivered(
            0,
            abi.encodePacked(
                L2MessageType_unsignedContractTx, gasLimit, maxFeePerGas, uint256(uint160(user)), value, data
            )
        );

        // send TX
        vm.prank(user);
        uint256 msgNum = inbox.sendContractTransaction(gasLimit, maxFeePerGas, user, value, data);

        //// checks
        assertEq(msgNum, 0, "Invalid msgNum");
        assertEq(bridge.delayedMessageCount(), 1, "Invalid delayed message count");
    }

    function test_sendContractTransaction_revert_WhenPaused() public {
        vm.prank(rollup);
        inbox.pause();

        vm.expectRevert("Pausable: paused");
        inbox.sendContractTransaction(10, 10, user, 10, abi.encodePacked("test data"));
    }

    function test_sendContractTransaction_revert_NotAllowed() public {
        vm.prank(rollup);
        inbox.setAllowListEnabled(true);

        vm.expectRevert(abi.encodeWithSelector(NotAllowedOrigin.selector, user));
        vm.prank(user, user);
        inbox.sendContractTransaction(10, 10, user, 10, abi.encodePacked("test data"));
    }

    function test_sendContractTransaction_revert_GasLimitTooLarge() public {
        uint256 tooBigGasLimit = uint256(type(uint64).max) + 1;

        vm.expectRevert(GasLimitTooLarge.selector);
        vm.prank(user);
        inbox.sendContractTransaction(tooBigGasLimit, 10, user, 10, abi.encodePacked("data"));
    }

    /**
     *
     * Event declarations
     *
     */
    event AllowListAddressSet(address indexed user, bool val);
    event AllowListEnabledUpdated(bool isEnabled);
    event InboxMessageDelivered(uint256 indexed messageNum, bytes data);
    event InboxMessageDeliveredFromOrigin(uint256 indexed messageNum);
}

contract InboxTest is AbsInboxTest {
    IInbox public ethInbox;

    function setUp() public {
        // deploy token, bridge and inbox
        bridge = IBridge(TestUtil.deployProxy(address(new Bridge())));
        inbox = IInboxBase(TestUtil.deployProxy(address(new Inbox(MAX_DATA_SIZE))));
        ethInbox = IInbox(address(inbox));

        // init bridge and inbox
        IEthBridge(address(bridge)).initialize(IOwnable(rollup));
        inbox.initialize(bridge, ISequencerInbox(seqInbox));

        address[] memory users = new address[](4);
        users[0] = 0x06FcD8264caF5c28D86eb4630c20004aa1faAaA8; // L2 customGateway
        users[1] = 0x340487b92808B84c2bd97C87B590EE81267E04a7; // L2 router
        users[2] = 0x87799989341A07F495287B1433eea98398FD73aA; // L2 standardGateway
        users[3] = 0xd563ECBDF90EBA783d0a218EFf158C1263ad02BE; // L2 wethGateway

        bool[] memory values = new bool[](4);
        values[0] = true;
        values[1] = true;
        values[2] = true;
        values[3] = true;

        vm.prank(rollup);
        Inbox(address(inbox)).setL2AllowList(users, values);

        vm.prank(rollup);
        bridge.setDelayedInbox(address(inbox), true);

        // fund user account
        vm.deal(user, 10 ether);
    }

    /* solhint-disable func-name-mixedcase */
    function test_initialize() public view {
        assertEq(address(inbox.bridge()), address(bridge), "Invalid bridge ref");
        assertEq(address(inbox.sequencerInbox()), seqInbox, "Invalid seqInbox ref");
        assertEq(inbox.allowListEnabled(), false, "Invalid allowListEnabled");
        assertEq((PausableUpgradeable(address(inbox))).paused(), false, "Invalid paused state");
    }

    // createRetryableTicket tests

    function test_createRetryableTicket_FromEOA_WhenToDifferentFromSender() public {
        uint256 bridgeEthBalanceBefore = address(bridge).balance;
        uint256 userEthBalanceBefore = address(user).balance;

        uint256 ethToSend = 0.3 ether;

        // retryable params
        uint256 l2CallValue = 0.1 ether;
        uint256 maxSubmissionCost = 0.1 ether;
        uint256 gasLimit = 100_000;
        uint256 maxFeePerGas = 0.000000002 ether;
        bytes memory data = abi.encodePacked("some msg");

        // expect event
        vm.expectEmit(true, true, true, true);
        emit InboxMessageDelivered(
            0,
            abi.encodePacked(
                uint256(uint160(111)),
                l2CallValue,
                ethToSend,
                maxSubmissionCost,
                uint256(uint160(user)),
                uint256(uint160(user)),
                gasLimit,
                maxFeePerGas,
                data.length,
                data
            )
        );

        // create retryable -> tx.origin == msg.sender
        vm.prank(user, user);
        ethInbox.createRetryableTicket{value: ethToSend}({
            to: address(111),
            l2CallValue: l2CallValue,
            maxSubmissionCost: maxSubmissionCost,
            excessFeeRefundAddress: user,
            callValueRefundAddress: user,
            gasLimit: gasLimit,
            maxFeePerGas: maxFeePerGas,
            data: data
        });

        //// checks

        uint256 bridgeEthBalanceAfter = address(bridge).balance;
        assertEq(bridgeEthBalanceAfter - bridgeEthBalanceBefore, ethToSend, "Invalid bridge token balance");

        uint256 userEthBalanceAfter = address(user).balance;
        assertEq(userEthBalanceBefore - userEthBalanceAfter, ethToSend, "Invalid user token balance");

        assertEq(bridge.delayedMessageCount(), 1, "Invalid delayed message count");
    }

    function test_createRetryableTicket_WhenAddressAllowed() public {
        address[4] memory allowedAddresses = [
            0x06FcD8264caF5c28D86eb4630c20004aa1faAaA8,
            0x340487b92808B84c2bd97C87B590EE81267E04a7,
            0x87799989341A07F495287B1433eea98398FD73aA,
            0xd563ECBDF90EBA783d0a218EFf158C1263ad02BE
        ];

        for (uint256 i = 0; i < allowedAddresses.length; i++) {
            user = allowedAddresses[i];
            vm.deal(user, 10 ether);

            uint256 bridgeEthBalanceBefore = address(bridge).balance;
            uint256 userEthBalanceBefore = address(user).balance;

            uint256 ethToSend = 0.3 ether;

            // retryable params
            uint256 l2CallValue = 0.1 ether;
            uint256 maxSubmissionCost = 0.1 ether;
            uint256 gasLimit = 100_000;
            uint256 maxFeePerGas = 0.000000002 ether;
            bytes memory data = abi.encodePacked("some msg");

            // expect event
            vm.expectEmit(true, true, true, true);
            emit InboxMessageDelivered(
                i,
                abi.encodePacked(
                    uint256(uint160(user)),
                    l2CallValue,
                    ethToSend,
                    maxSubmissionCost,
                    uint256(uint160(user)),
                    uint256(uint160(user)),
                    gasLimit,
                    maxFeePerGas,
                    data.length,
                    data
                )
            );

            vm.prank(user);
            ethInbox.createRetryableTicket{value: ethToSend}({
                to: address(user),
                l2CallValue: l2CallValue,
                maxSubmissionCost: maxSubmissionCost,
                excessFeeRefundAddress: user,
                callValueRefundAddress: user,
                gasLimit: gasLimit,
                maxFeePerGas: maxFeePerGas,
                data: data
            });

            //// checks

            uint256 bridgeEthBalanceAfter = address(bridge).balance;
            assertEq(bridgeEthBalanceAfter - bridgeEthBalanceBefore, ethToSend, "Invalid bridge token balance");

            uint256 userEthBalanceAfter = address(user).balance;
            assertEq(userEthBalanceBefore - userEthBalanceAfter, ethToSend, "Invalid user token balance");

            assertEq(bridge.delayedMessageCount(), i + 1, "Invalid delayed message count");
        }
    }

    function test_createRetryableTicket_WhenAddressAllowed_WhenExcessFeeRefundAddressDiffFromSender() public {
        address[4] memory allowedAddresses = [
            0x06FcD8264caF5c28D86eb4630c20004aa1faAaA8,
            0x340487b92808B84c2bd97C87B590EE81267E04a7,
            0x87799989341A07F495287B1433eea98398FD73aA,
            0xd563ECBDF90EBA783d0a218EFf158C1263ad02BE
        ];

        for (uint256 i = 0; i < allowedAddresses.length; i++) {
            user = allowedAddresses[i];
            vm.deal(user, 10 ether);

            uint256 bridgeEthBalanceBefore = address(bridge).balance;
            uint256 userEthBalanceBefore = address(user).balance;

            uint256 ethToSend = 0.3 ether;

            // retryable params
            uint256 l2CallValue = 0.1 ether;
            uint256 maxSubmissionCost = 0.1 ether;
            uint256 gasLimit = 100_000;
            uint256 maxFeePerGas = 0.000000002 ether;
            bytes memory data = abi.encodePacked("some msg");

            // expect event
            vm.expectEmit(true, true, true, true);
            emit InboxMessageDelivered(
                i,
                abi.encodePacked(
                    uint256(uint160(user)),
                    l2CallValue,
                    ethToSend,
                    maxSubmissionCost,
                    uint256(uint160(123)),
                    uint256(uint160(user)),
                    gasLimit,
                    maxFeePerGas,
                    data.length,
                    data
                )
            );

            vm.prank(user);
            ethInbox.createRetryableTicket{value: ethToSend}({
                to: address(user),
                l2CallValue: l2CallValue,
                maxSubmissionCost: maxSubmissionCost,
                excessFeeRefundAddress: address(123),
                callValueRefundAddress: user,
                gasLimit: gasLimit,
                maxFeePerGas: maxFeePerGas,
                data: data
            });

            //// checks

            uint256 bridgeEthBalanceAfter = address(bridge).balance;
            assertEq(bridgeEthBalanceAfter - bridgeEthBalanceBefore, ethToSend, "Invalid bridge token balance");

            uint256 userEthBalanceAfter = address(user).balance;
            assertEq(userEthBalanceBefore - userEthBalanceAfter, ethToSend, "Invalid user token balance");

            assertEq(bridge.delayedMessageCount(), i + 1, "Invalid delayed message count");
        }
    }

    function test_createRetryableTicket_WhenAddressAllowed_WhenCallValueRefundAddressDiffFromSender() public {
        address[4] memory allowedAddresses = [
            0x06FcD8264caF5c28D86eb4630c20004aa1faAaA8,
            0x340487b92808B84c2bd97C87B590EE81267E04a7,
            0x87799989341A07F495287B1433eea98398FD73aA,
            0xd563ECBDF90EBA783d0a218EFf158C1263ad02BE
        ];

        for (uint256 i = 0; i < allowedAddresses.length; i++) {
            user = allowedAddresses[i];
            vm.deal(user, 10 ether);

            uint256 bridgeEthBalanceBefore = address(bridge).balance;
            uint256 userEthBalanceBefore = address(user).balance;

            uint256 ethToSend = 0.3 ether;

            // retryable params
            uint256 l2CallValue = 0.1 ether;
            uint256 maxSubmissionCost = 0.1 ether;
            uint256 gasLimit = 100_000;
            uint256 maxFeePerGas = 0.000000002 ether;
            bytes memory data = abi.encodePacked("some msg");

            // expect event
            vm.expectEmit(true, true, true, true);
            emit InboxMessageDelivered(
                i,
                abi.encodePacked(
                    uint256(uint160(user)),
                    l2CallValue,
                    ethToSend,
                    maxSubmissionCost,
                    uint256(uint160(user)),
                    uint256(uint160(123)),
                    gasLimit,
                    maxFeePerGas,
                    data.length,
                    data
                )
            );

            vm.prank(user);
            ethInbox.createRetryableTicket{value: ethToSend}({
                to: address(user),
                l2CallValue: l2CallValue,
                maxSubmissionCost: maxSubmissionCost,
                excessFeeRefundAddress: user,
                callValueRefundAddress: address(123),
                gasLimit: gasLimit,
                maxFeePerGas: maxFeePerGas,
                data: data
            });

            //// checks

            uint256 bridgeEthBalanceAfter = address(bridge).balance;
            assertEq(bridgeEthBalanceAfter - bridgeEthBalanceBefore, ethToSend, "Invalid bridge token balance");

            uint256 userEthBalanceAfter = address(user).balance;
            assertEq(userEthBalanceBefore - userEthBalanceAfter, ethToSend, "Invalid user token balance");

            assertEq(bridge.delayedMessageCount(), i + 1, "Invalid delayed message count");
        }
    }

    function test_createRetryableTicket_WhenAddressAllowed_WhenRefundAddressesDiffFromSender() public {
        address[4] memory allowedAddresses = [
            0x06FcD8264caF5c28D86eb4630c20004aa1faAaA8,
            0x340487b92808B84c2bd97C87B590EE81267E04a7,
            0x87799989341A07F495287B1433eea98398FD73aA,
            0xd563ECBDF90EBA783d0a218EFf158C1263ad02BE
        ];

        for (uint256 i = 0; i < allowedAddresses.length; i++) {
            user = allowedAddresses[i];
            vm.deal(user, 10 ether);

            uint256 bridgeEthBalanceBefore = address(bridge).balance;
            uint256 userEthBalanceBefore = address(user).balance;

            uint256 ethToSend = 0.3 ether;

            // retryable params
            uint256 l2CallValue = 0.1 ether;
            uint256 maxSubmissionCost = 0.1 ether;
            uint256 gasLimit = 100_000;
            uint256 maxFeePerGas = 0.000000002 ether;
            bytes memory data = abi.encodePacked("some msg");

            // expect event
            vm.expectEmit(true, true, true, true);
            emit InboxMessageDelivered(
                i,
                abi.encodePacked(
                    uint256(uint160(user)),
                    l2CallValue,
                    ethToSend,
                    maxSubmissionCost,
                    uint256(uint160(123)),
                    uint256(uint160(456)),
                    gasLimit,
                    maxFeePerGas,
                    data.length,
                    data
                )
            );

            vm.prank(user);
            ethInbox.createRetryableTicket{value: ethToSend}({
                to: address(user),
                l2CallValue: l2CallValue,
                maxSubmissionCost: maxSubmissionCost,
                excessFeeRefundAddress: address(123),
                callValueRefundAddress: address(456),
                gasLimit: gasLimit,
                maxFeePerGas: maxFeePerGas,
                data: data
            });

            //// checks

            uint256 bridgeEthBalanceAfter = address(bridge).balance;
            assertEq(bridgeEthBalanceAfter - bridgeEthBalanceBefore, ethToSend, "Invalid bridge token balance");

            uint256 userEthBalanceAfter = address(user).balance;
            assertEq(userEthBalanceBefore - userEthBalanceAfter, ethToSend, "Invalid user token balance");

            assertEq(bridge.delayedMessageCount(), i + 1, "Invalid delayed message count");
        }
    }

    function test_createRetryableTicket_RevertWhen_ExcessFeeRefundAddressDiffFromSender() public {
        uint256 bridgeEthBalanceBefore = address(bridge).balance;
        uint256 userEthBalanceBefore = address(user).balance;

        uint256 ethToSend = 0.3 ether;

        // retryable params
        uint256 l2CallValue = 0.1 ether;
        uint256 maxSubmissionCost = 0.1 ether;
        uint256 gasLimit = 100_000;
        uint256 maxFeePerGas = 0.000000002 ether;
        bytes memory data = abi.encodePacked("some msg");

        // create retryable -> tx.origin == msg.sender
        vm.prank(user, user);
        vm.expectRevert(
            abi.encodeWithSelector(
                AbsInbox.RefundAddressNotAllowed.selector, address(user), address(123), address(user)
            )
        );
        ethInbox.createRetryableTicket{value: ethToSend}({
            to: address(user),
            l2CallValue: l2CallValue,
            maxSubmissionCost: maxSubmissionCost,
            excessFeeRefundAddress: address(123),
            callValueRefundAddress: user,
            gasLimit: gasLimit,
            maxFeePerGas: maxFeePerGas,
            data: data
        });

        //// checks

        uint256 bridgeEthBalanceAfter = address(bridge).balance;
        assertEq(bridgeEthBalanceAfter, bridgeEthBalanceBefore, "Invalid bridge token balance");

        uint256 userEthBalanceAfter = address(user).balance;
        assertEq(userEthBalanceAfter, userEthBalanceBefore, "Invalid user token balance");

        assertEq(bridge.delayedMessageCount(), 0, "Invalid delayed message count");
    }

    function test_createRetryableTicket_RevertWhen_CallValueRefundAddressDiffFromSender() public {
        uint256 bridgeEthBalanceBefore = address(bridge).balance;
        uint256 userEthBalanceBefore = address(user).balance;

        uint256 ethToSend = 0.3 ether;

        // retryable params
        uint256 l2CallValue = 0.1 ether;
        uint256 maxSubmissionCost = 0.1 ether;
        uint256 gasLimit = 100_000;
        uint256 maxFeePerGas = 0.000000002 ether;
        bytes memory data = abi.encodePacked("some msg");

        // create retryable -> tx.origin == msg.sender
        vm.prank(user, user);
        vm.expectRevert(
            abi.encodeWithSelector(
                AbsInbox.RefundAddressNotAllowed.selector, address(user), address(user), address(123)
            )
        );
        ethInbox.createRetryableTicket{value: ethToSend}({
            to: address(user),
            l2CallValue: l2CallValue,
            maxSubmissionCost: maxSubmissionCost,
            excessFeeRefundAddress: user,
            callValueRefundAddress: address(123),
            gasLimit: gasLimit,
            maxFeePerGas: maxFeePerGas,
            data: data
        });

        //// checks

        uint256 bridgeEthBalanceAfter = address(bridge).balance;
        assertEq(bridgeEthBalanceAfter, bridgeEthBalanceBefore, "Invalid bridge token balance");

        uint256 userEthBalanceAfter = address(user).balance;
        assertEq(userEthBalanceAfter, userEthBalanceBefore, "Invalid user token balance");

        assertEq(bridge.delayedMessageCount(), 0, "Invalid delayed message count");
    }

    function test_createRetryableTicket_RevertWhen_RefundAddressesDiffFromSender() public {
        uint256 bridgeEthBalanceBefore = address(bridge).balance;
        uint256 userEthBalanceBefore = address(user).balance;

        uint256 ethToSend = 0.3 ether;

        // retryable params
        uint256 l2CallValue = 0.1 ether;
        uint256 maxSubmissionCost = 0.1 ether;
        uint256 gasLimit = 100_000;
        uint256 maxFeePerGas = 0.000000002 ether;
        bytes memory data = abi.encodePacked("some msg");

        // create retryable -> tx.origin == msg.sender
        vm.prank(user, user);
        vm.expectRevert(
            abi.encodeWithSelector(AbsInbox.RefundAddressNotAllowed.selector, address(user), address(123), address(456))
        );
        ethInbox.createRetryableTicket{value: ethToSend}({
            to: address(user),
            l2CallValue: l2CallValue,
            maxSubmissionCost: maxSubmissionCost,
            excessFeeRefundAddress: address(123),
            callValueRefundAddress: address(456),
            gasLimit: gasLimit,
            maxFeePerGas: maxFeePerGas,
            data: data
        });

        //// checks

        uint256 bridgeEthBalanceAfter = address(bridge).balance;
        assertEq(bridgeEthBalanceAfter, bridgeEthBalanceBefore, "Invalid bridge token balance");

        uint256 userEthBalanceAfter = address(user).balance;
        assertEq(userEthBalanceAfter, userEthBalanceBefore, "Invalid user token balance");

        assertEq(bridge.delayedMessageCount(), 0, "Invalid delayed message count");
    }

    // unsafeCreateRetryableTicket tests

    function test_unsafeCreateRetryableTicket_RevertWhen_ExcessFeeRefundAddressDiffFromSender() public {
        uint256 bridgeEthBalanceBefore = address(bridge).balance;
        uint256 userEthBalanceBefore = address(user).balance;

        uint256 ethToSend = 0.3 ether;

        // retryable params
        uint256 l2CallValue = 0.1 ether;
        uint256 maxSubmissionCost = 0.1 ether;
        uint256 gasLimit = 100_000;
        uint256 maxFeePerGas = 0.000000002 ether;
        bytes memory data = abi.encodePacked("some msg");

        // create retryable -> tx.origin == msg.sender
        vm.prank(user, user);
        vm.expectRevert(
            abi.encodeWithSelector(
                AbsInbox.RefundAddressNotAllowed.selector, address(user), address(123), address(user)
            )
        );
        ethInbox.unsafeCreateRetryableTicket{value: ethToSend}({
            to: address(user),
            l2CallValue: l2CallValue,
            maxSubmissionCost: maxSubmissionCost,
            excessFeeRefundAddress: address(123),
            callValueRefundAddress: user,
            gasLimit: gasLimit,
            maxFeePerGas: maxFeePerGas,
            data: data
        });

        //// checks

        uint256 bridgeEthBalanceAfter = address(bridge).balance;
        assertEq(bridgeEthBalanceAfter, bridgeEthBalanceBefore, "Invalid bridge token balance");

        uint256 userEthBalanceAfter = address(user).balance;
        assertEq(userEthBalanceAfter, userEthBalanceBefore, "Invalid user token balance");

        assertEq(bridge.delayedMessageCount(), 0, "Invalid delayed message count");
    }

    function test_unsafeCreateRetryableTicket_RevertWhen_CallValueRefundAddressDiffFromSender() public {
        uint256 bridgeEthBalanceBefore = address(bridge).balance;
        uint256 userEthBalanceBefore = address(user).balance;

        uint256 ethToSend = 0.3 ether;

        // retryable params
        uint256 l2CallValue = 0.1 ether;
        uint256 maxSubmissionCost = 0.1 ether;
        uint256 gasLimit = 100_000;
        uint256 maxFeePerGas = 0.000000002 ether;
        bytes memory data = abi.encodePacked("some msg");

        // create retryable -> tx.origin == msg.sender
        vm.prank(user, user);
        vm.expectRevert(
            abi.encodeWithSelector(
                AbsInbox.RefundAddressNotAllowed.selector, address(user), address(user), address(123)
            )
        );
        ethInbox.unsafeCreateRetryableTicket{value: ethToSend}({
            to: address(user),
            l2CallValue: l2CallValue,
            maxSubmissionCost: maxSubmissionCost,
            excessFeeRefundAddress: user,
            callValueRefundAddress: address(123),
            gasLimit: gasLimit,
            maxFeePerGas: maxFeePerGas,
            data: data
        });

        //// checks

        uint256 bridgeEthBalanceAfter = address(bridge).balance;
        assertEq(bridgeEthBalanceAfter, bridgeEthBalanceBefore, "Invalid bridge token balance");

        uint256 userEthBalanceAfter = address(user).balance;
        assertEq(userEthBalanceAfter, userEthBalanceBefore, "Invalid user token balance");

        assertEq(bridge.delayedMessageCount(), 0, "Invalid delayed message count");
    }

    function test_unsafeCreateRetryableTicket_RevertWhen_RefundAddressesDiffFromSender() public {
        uint256 bridgeEthBalanceBefore = address(bridge).balance;
        uint256 userEthBalanceBefore = address(user).balance;

        uint256 ethToSend = 0.3 ether;

        // retryable params
        uint256 l2CallValue = 0.1 ether;
        uint256 maxSubmissionCost = 0.1 ether;
        uint256 gasLimit = 100_000;
        uint256 maxFeePerGas = 0.000000002 ether;
        bytes memory data = abi.encodePacked("some msg");

        // create retryable -> tx.origin == msg.sender
        vm.prank(user, user);
        vm.expectRevert(
            abi.encodeWithSelector(AbsInbox.RefundAddressNotAllowed.selector, address(user), address(123), address(456))
        );
        ethInbox.unsafeCreateRetryableTicket{value: ethToSend}({
            to: address(user),
            l2CallValue: l2CallValue,
            maxSubmissionCost: maxSubmissionCost,
            excessFeeRefundAddress: address(123),
            callValueRefundAddress: address(456),
            gasLimit: gasLimit,
            maxFeePerGas: maxFeePerGas,
            data: data
        });

        //// checks

        uint256 bridgeEthBalanceAfter = address(bridge).balance;
        assertEq(bridgeEthBalanceAfter, bridgeEthBalanceBefore, "Invalid bridge token balance");

        uint256 userEthBalanceAfter = address(user).balance;
        assertEq(userEthBalanceAfter, userEthBalanceBefore, "Invalid user token balance");

        assertEq(bridge.delayedMessageCount(), 0, "Invalid delayed message count");
    }

    ////// below tests are taken as is from Inbox.t.sol //////

    function test_depositEth_FromEOA() public {
        uint256 depositAmount = 2 ether;

        uint256 bridgeEthBalanceBefore = address(bridge).balance;
        uint256 userEthBalanceBefore = address(user).balance;

        // expect event
        vm.expectEmit(true, true, true, true);
        emit InboxMessageDelivered(0, abi.encodePacked(user, depositAmount));

        // deposit tokens -> tx.origin == msg.sender
        vm.prank(user, user);
        ethInbox.depositEth{value: depositAmount}();

        //// checks

        uint256 bridgeEthBalanceAfter = address(bridge).balance;
        assertEq(bridgeEthBalanceAfter - bridgeEthBalanceBefore, depositAmount, "Invalid bridge eth balance");

        uint256 userEthBalanceAfter = address(user).balance;
        assertEq(userEthBalanceBefore - userEthBalanceAfter, depositAmount, "Invalid user eth balance");

        assertEq(bridge.delayedMessageCount(), 1, "Invalid delayed message count");
    }

    function test_depositEth_FromContract() public {
        uint256 depositAmount = 1.2 ether;

        uint256 bridgeEthBalanceBefore = address(bridge).balance;
        uint256 userEthBalanceBefore = address(user).balance;

        // expect event
        vm.expectEmit(true, true, true, true);
        emit InboxMessageDelivered(0, abi.encodePacked(AddressAliasHelper.applyL1ToL2Alias(user), depositAmount));

        // deposit tokens -> tx.origin != msg.sender
        vm.prank(user);
        ethInbox.depositEth{value: depositAmount}();

        //// checks

        uint256 bridgeEthBalanceAfter = address(bridge).balance;
        assertEq(bridgeEthBalanceAfter - bridgeEthBalanceBefore, depositAmount, "Invalid bridge eth balance");

        uint256 userEthBalanceAfter = address(user).balance;
        assertEq(userEthBalanceBefore - userEthBalanceAfter, depositAmount, "Invalid eth token balance");

        assertEq(bridge.delayedMessageCount(), 1, "Invalid delayed message count");
    }

    function test_depositEth_revert_EthTransferFails() public {
        uint256 bridgeEthBalanceBefore = address(bridge).balance;
        uint256 userEthBalanceBefore = address(user).balance;

        // deposit too many eth shall fail
        vm.prank(user);
        uint256 invalidDepositAmount = 300 ether;
        vm.expectRevert();
        ethInbox.depositEth{value: invalidDepositAmount}();

        //// checks

        uint256 bridgeEthBalanceAfter = address(bridge).balance;
        assertEq(bridgeEthBalanceAfter, bridgeEthBalanceBefore, "Invalid bridge token balance");

        uint256 userEthBalanceAfter = address(user).balance;
        assertEq(userEthBalanceBefore, userEthBalanceAfter, "Invalid user token balance");

        assertEq(bridge.delayedMessageCount(), 0, "Invalid delayed message count");
    }

    function test_createRetryableTicket_FromEOA() public {
        uint256 bridgeEthBalanceBefore = address(bridge).balance;
        uint256 userEthBalanceBefore = address(user).balance;

        uint256 ethToSend = 0.3 ether;

        // retryable params
        uint256 l2CallValue = 0.1 ether;
        uint256 maxSubmissionCost = 0.1 ether;
        uint256 gasLimit = 100_000;
        uint256 maxFeePerGas = 0.000000002 ether;
        bytes memory data = abi.encodePacked("some msg");

        // expect event
        vm.expectEmit(true, true, true, true);
        emit InboxMessageDelivered(
            0,
            abi.encodePacked(
                uint256(uint160(user)),
                l2CallValue,
                ethToSend,
                maxSubmissionCost,
                uint256(uint160(user)),
                uint256(uint160(user)),
                gasLimit,
                maxFeePerGas,
                data.length,
                data
            )
        );

        // create retryable -> tx.origin == msg.sender
        vm.prank(user, user);
        ethInbox.createRetryableTicket{value: ethToSend}({
            to: address(user),
            l2CallValue: l2CallValue,
            maxSubmissionCost: maxSubmissionCost,
            excessFeeRefundAddress: user,
            callValueRefundAddress: user,
            gasLimit: gasLimit,
            maxFeePerGas: maxFeePerGas,
            data: data
        });

        //// checks

        uint256 bridgeEthBalanceAfter = address(bridge).balance;
        assertEq(bridgeEthBalanceAfter - bridgeEthBalanceBefore, ethToSend, "Invalid bridge token balance");

        uint256 userEthBalanceAfter = address(user).balance;
        assertEq(userEthBalanceBefore - userEthBalanceAfter, ethToSend, "Invalid user token balance");

        assertEq(bridge.delayedMessageCount(), 1, "Invalid delayed message count");
    }

    function test_createRetryableTicket_FromContract() public {
        address sender = address(new Sender());
        vm.deal(sender, 10 ether);

        uint256 bridgeEthBalanceBefore = address(bridge).balance;
        uint256 senderEthBalanceBefore = sender.balance;

        uint256 ethToSend = 0.3 ether;

        // retryable params
        uint256 l2CallValue = 0.1 ether;
        uint256 maxSubmissionCost = 0.1 ether;
        uint256 gasLimit = 100_000;
        uint256 maxFeePerGas = 0.000000001 ether;

        // expect event
        uint256 uintAlias = uint256(uint160(AddressAliasHelper.applyL1ToL2Alias(sender)));
        vm.expectEmit(true, true, true, true);
        emit InboxMessageDelivered(
            0,
            abi.encodePacked(
                uint256(uint160(sender)),
                l2CallValue,
                ethToSend,
                maxSubmissionCost,
                uintAlias,
                uintAlias,
                gasLimit,
                maxFeePerGas,
                abi.encodePacked("some msg").length,
                abi.encodePacked("some msg")
            )
        );

        // create retryable
        vm.prank(sender);
        ethInbox.createRetryableTicket{value: ethToSend}({
            to: sender,
            l2CallValue: l2CallValue,
            maxSubmissionCost: maxSubmissionCost,
            excessFeeRefundAddress: sender,
            callValueRefundAddress: sender,
            gasLimit: gasLimit,
            maxFeePerGas: maxFeePerGas,
            data: abi.encodePacked("some msg")
        });

        //// checks

        uint256 bridgeEthBalanceAfter = address(bridge).balance;
        assertEq(bridgeEthBalanceAfter - bridgeEthBalanceBefore, ethToSend, "Invalid bridge token balance");

        uint256 senderEthBalanceAfter = address(sender).balance;
        assertEq(senderEthBalanceBefore - senderEthBalanceAfter, ethToSend, "Invalid sender token balance");

        assertEq(bridge.delayedMessageCount(), 1, "Invalid delayed message count");
    }

    function test_createRetryableTicket_revert_WhenPaused() public {
        vm.prank(rollup);
        inbox.pause();

        vm.expectRevert("Pausable: paused");
        ethInbox.createRetryableTicket({
            to: user,
            l2CallValue: 100,
            maxSubmissionCost: 0,
            excessFeeRefundAddress: user,
            callValueRefundAddress: user,
            gasLimit: 10,
            maxFeePerGas: 1,
            data: abi.encodePacked("data")
        });
    }

    function test_createRetryableTicket_revert_OnlyAllowed() public {
        vm.prank(rollup);
        inbox.setAllowListEnabled(true);

        vm.prank(user, user);
        vm.expectRevert(abi.encodeWithSelector(NotAllowedOrigin.selector, user));
        ethInbox.createRetryableTicket({
            to: user,
            l2CallValue: 100,
            maxSubmissionCost: 0,
            excessFeeRefundAddress: user,
            callValueRefundAddress: user,
            gasLimit: 10,
            maxFeePerGas: 1,
            data: abi.encodePacked("data")
        });
    }

    function test_createRetryableTicket_revert_InsufficientValue() public {
        uint256 tooSmallEthAmount = 1 ether;
        uint256 l2CallValue = 2 ether;
        uint256 maxSubmissionCost = 0.1 ether;
        uint256 gasLimit = 200000;
        uint256 maxFeePerGas = 0.00000002 ether;

        vm.prank(user, user);
        vm.expectRevert(
            abi.encodeWithSelector(
                InsufficientValue.selector, maxSubmissionCost + l2CallValue + gasLimit * maxFeePerGas, tooSmallEthAmount
            )
        );
        ethInbox.createRetryableTicket{value: tooSmallEthAmount}({
            to: user,
            l2CallValue: l2CallValue,
            maxSubmissionCost: maxSubmissionCost,
            excessFeeRefundAddress: user,
            callValueRefundAddress: user,
            gasLimit: gasLimit,
            maxFeePerGas: maxFeePerGas,
            data: abi.encodePacked("data")
        });
    }

    function test_createRetryableTicket_revert_RetryableDataTracer() public {
        uint256 msgValue = 3 ether;
        uint256 l2CallValue = 1 ether;
        uint256 maxSubmissionCost = 0.1 ether;
        uint256 gasLimit = 100000;
        uint256 maxFeePerGas = 1;
        bytes memory data = abi.encodePacked("xy");

        // revert as maxFeePerGas == 1 is magic value
        vm.prank(user, user);
        vm.expectRevert(
            abi.encodeWithSelector(
                RetryableData.selector,
                user,
                user,
                l2CallValue,
                msgValue,
                maxSubmissionCost,
                user,
                user,
                gasLimit,
                maxFeePerGas,
                data
            )
        );
        ethInbox.createRetryableTicket{value: msgValue}({
            to: user,
            l2CallValue: l2CallValue,
            maxSubmissionCost: maxSubmissionCost,
            excessFeeRefundAddress: user,
            callValueRefundAddress: user,
            gasLimit: gasLimit,
            maxFeePerGas: maxFeePerGas,
            data: data
        });

        gasLimit = 1;
        maxFeePerGas = 2;

        // revert as gasLimit == 1 is magic value
        vm.prank(user, user);
        vm.expectRevert(
            abi.encodeWithSelector(
                RetryableData.selector,
                user,
                user,
                l2CallValue,
                msgValue,
                maxSubmissionCost,
                user,
                user,
                gasLimit,
                maxFeePerGas,
                data
            )
        );
        ethInbox.createRetryableTicket{value: msgValue}({
            to: user,
            l2CallValue: l2CallValue,
            maxSubmissionCost: maxSubmissionCost,
            excessFeeRefundAddress: user,
            callValueRefundAddress: user,
            gasLimit: gasLimit,
            maxFeePerGas: maxFeePerGas,
            data: data
        });
    }

    function test_createRetryableTicket_revert_GasLimitTooLarge() public {
        uint256 tooBigGasLimit = uint256(type(uint64).max) + 1;

        vm.deal(user, uint256(type(uint64).max) * 3);
        vm.prank(user, user);
        vm.expectRevert(GasLimitTooLarge.selector);
        ethInbox.createRetryableTicket{value: uint256(type(uint64).max) * 3}({
            to: user,
            l2CallValue: 100,
            maxSubmissionCost: 0,
            excessFeeRefundAddress: user,
            callValueRefundAddress: user,
            gasLimit: tooBigGasLimit,
            maxFeePerGas: 2,
            data: abi.encodePacked("data")
        });
    }

    function test_createRetryableTicket_revert_InsufficientSubmissionCost() public {
        uint256 tooSmallMaxSubmissionCost = 5;
        bytes memory data = abi.encodePacked("msg");

        // simulate 23 gwei basefee
        vm.fee(23000000000);
        uint256 submissionFee = ethInbox.calculateRetryableSubmissionFee(data.length, block.basefee);

        // call shall revert
        vm.prank(user, user);
        vm.expectRevert(abi.encodePacked(InsufficientSubmissionCost.selector, submissionFee, tooSmallMaxSubmissionCost));
        ethInbox.createRetryableTicket{value: 1 ether}({
            to: user,
            l2CallValue: 100,
            maxSubmissionCost: tooSmallMaxSubmissionCost,
            excessFeeRefundAddress: user,
            callValueRefundAddress: user,
            gasLimit: 60000,
            maxFeePerGas: 0.00000001 ether,
            data: data
        });
    }

    function test_unsafeCreateRetryableTicket_FromEOA() public {
        uint256 bridgeEthBalanceBefore = address(bridge).balance;
        uint256 userEthBalanceBefore = address(user).balance;

        uint256 ethToSend = 0.3 ether;

        // retryable params
        uint256 l2CallValue = 0.1 ether;
        uint256 maxSubmissionCost = 0.1 ether;
        uint256 gasLimit = 100_000;
        uint256 maxFeePerGas = 0.000000002 ether;
        bytes memory data = abi.encodePacked("some msg");

        // expect event
        vm.expectEmit(true, true, true, true);
        emit InboxMessageDelivered(
            0,
            abi.encodePacked(
                uint256(uint160(user)),
                l2CallValue,
                ethToSend,
                maxSubmissionCost,
                uint256(uint160(user)),
                uint256(uint160(user)),
                gasLimit,
                maxFeePerGas,
                data.length,
                data
            )
        );

        // create retryable -> tx.origin == msg.sender
        vm.prank(user, user);
        ethInbox.unsafeCreateRetryableTicket{value: ethToSend}({
            to: address(user),
            l2CallValue: l2CallValue,
            maxSubmissionCost: maxSubmissionCost,
            excessFeeRefundAddress: user,
            callValueRefundAddress: user,
            gasLimit: gasLimit,
            maxFeePerGas: maxFeePerGas,
            data: data
        });

        //// checks

        uint256 bridgeEthBalanceAfter = address(bridge).balance;
        assertEq(bridgeEthBalanceAfter - bridgeEthBalanceBefore, ethToSend, "Invalid bridge token balance");

        uint256 userEthBalanceAfter = address(user).balance;
        assertEq(userEthBalanceBefore - userEthBalanceAfter, ethToSend, "Invalid user token balance");

        assertEq(bridge.delayedMessageCount(), 1, "Invalid delayed message count");
    }

    function test_unsafeCreateRetryableTicket_FromContract() public {
        address sender = address(new Sender());
        vm.deal(sender, 10 ether);

        uint256 bridgeEthBalanceBefore = address(bridge).balance;
        uint256 senderEthBalanceBefore = sender.balance;

        uint256 ethToSend = 0.3 ether;

        // retryable params
        uint256 l2CallValue = 0.1 ether;
        uint256 maxSubmissionCost = 0.1 ether;
        uint256 gasLimit = 100_000;
        uint256 maxFeePerGas = 0.000000001 ether;

        // expect event
        vm.expectEmit(true, true, true, true);
        emit InboxMessageDelivered(
            0,
            abi.encodePacked(
                uint256(uint160(sender)),
                l2CallValue,
                ethToSend,
                maxSubmissionCost,
                uint256(uint160(sender)),
                uint256(uint160(sender)),
                gasLimit,
                maxFeePerGas,
                abi.encodePacked("some msg").length,
                abi.encodePacked("some msg")
            )
        );

        // create retryable
        vm.prank(sender);
        ethInbox.unsafeCreateRetryableTicket{value: ethToSend}({
            to: sender,
            l2CallValue: l2CallValue,
            maxSubmissionCost: maxSubmissionCost,
            excessFeeRefundAddress: sender,
            callValueRefundAddress: sender,
            gasLimit: gasLimit,
            maxFeePerGas: maxFeePerGas,
            data: abi.encodePacked("some msg")
        });

        //// checks

        uint256 bridgeEthBalanceAfter = address(bridge).balance;
        assertEq(bridgeEthBalanceAfter - bridgeEthBalanceBefore, ethToSend, "Invalid bridge token balance");

        uint256 senderEthBalanceAfter = address(sender).balance;
        assertEq(senderEthBalanceBefore - senderEthBalanceAfter, ethToSend, "Invalid sender token balance");

        assertEq(bridge.delayedMessageCount(), 1, "Invalid delayed message count");
    }

    function test_unsafeCreateRetryableTicket_NotRevertingOnInsufficientValue() public {
        uint256 bridgeEthBalanceBefore = address(bridge).balance;
        uint256 userEthBalanceBefore = address(user).balance;

        uint256 tooSmallEthAmount = 1 ether;
        uint256 l2CallValue = 2 ether;
        uint256 maxSubmissionCost = 0.1 ether;
        uint256 gasLimit = 200000;
        uint256 maxFeePerGas = 0.00000002 ether;

        // expect event
        vm.expectEmit(true, true, true, true);
        emit InboxMessageDelivered(
            0,
            abi.encodePacked(
                uint256(uint160(user)),
                l2CallValue,
                tooSmallEthAmount,
                maxSubmissionCost,
                uint256(uint160(user)),
                uint256(uint160(user)),
                gasLimit,
                maxFeePerGas,
                abi.encodePacked("data").length,
                abi.encodePacked("data")
            )
        );

        vm.prank(user, user);
        ethInbox.unsafeCreateRetryableTicket{value: tooSmallEthAmount}({
            to: user,
            l2CallValue: l2CallValue,
            maxSubmissionCost: maxSubmissionCost,
            excessFeeRefundAddress: user,
            callValueRefundAddress: user,
            gasLimit: gasLimit,
            maxFeePerGas: maxFeePerGas,
            data: abi.encodePacked("data")
        });

        //// checks

        uint256 bridgeEthBalanceAfter = address(bridge).balance;
        assertEq(bridgeEthBalanceAfter - bridgeEthBalanceBefore, tooSmallEthAmount, "Invalid bridge token balance");

        uint256 userEthBalanceAfter = address(user).balance;
        assertEq(userEthBalanceBefore - userEthBalanceAfter, tooSmallEthAmount, "Invalid user token balance");

        assertEq(bridge.delayedMessageCount(), 1, "Invalid delayed message count");
    }

    function test_calculateRetryableSubmissionFee() public {
        // 30 gwei fee
        uint256 basefee = 30000000000;
        vm.fee(basefee);
        uint256 datalength = 10;

        assertEq(
            inbox.calculateRetryableSubmissionFee(datalength, 0),
            (1400 + 6 * datalength) * basefee,
            "Invalid eth retryable submission fee"
        );
    }
}
