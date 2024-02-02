// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@aa/interfaces/IAggregator.sol";

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../SharedSetup.t.sol";
import "../../script/migrations/utils/MigrationHelper.sol";

/// @dev to run this tests use the following command:
/// `forge script ./test/clause7/clause7.t.sol:Clause7thTestScript --rpc-url $KINTO_RPC_URL -vvvv --broadcast --skip-simulation`
/// and uncomment the test you want to run one by one
/// you must MANUALLY check that the error messages match the expected ones
contract Clause7thTestScript is MigrationHelper {
    uint256 public constant KINTO_RULES_BLOCK_START = 100;
    uint256 senderPk = vm.envUint("KINTO_TESTNET_PRIVATE_KEY");
    address sender = vm.addr(senderPk);

    EntryPoint _entryPoint = EntryPoint(payable(address(0x351110fC667dA12B5d07AEDaE6e90f17BAF512C0)));
    IKintoID _kintoID = IKintoID(address(0xD5e0E7342Ad607516e177fDC9133E38e1a57679A));
    IKintoWalletFactory _factory = IKintoWalletFactory(address(0xDed93a06edd053538c8F6b9A5ee07a45Fc590Fa4));
    SponsorPaymaster _paymaster = SponsorPaymaster(address(0x77d878C48d13e11F0932616a0c43306cf17A2e25));

    function run() public {
        require(block.number > KINTO_RULES_BLOCK_START);
        console.log("Sending txs from: ", sender);
        console.log("Current block is ", block.number);
        console.log("Current chain ID is ", block.chainid);

        // testAssertSelectors();
        // testTransaction_RevertWhen_ContractDeployment();
        // testTransaction_WhenTargetIsAllowed();

        // entrypoint withdraw to tests
        // testTransaction_WhenTargetIsEntryPoint_WhenWithdrawTo_WhenAddressIsSender();
        // testTransaction_RevertWhen_WhenTargetIsEntryPoint_WhenWithdrawTo_WhenAddressIsNotSender(); // FIXME

        // entrypoint withdraw stake tests
        // testTransaction_WhenTargetIsEntryPoint_WhenWithdrawStake_WhenAddressIsSender();
        // testTransaction_RevertWhen_WhenTargetIsEntryPoint_WhenWithdrawStake_WhenAddressIsNotSender();

        // entrypoint handle ops tests
        // testTransaction_WhenTargetIsEntryPoint_WhenHandleOps_WhenBeneficiaryIsSender(); // FIXME!!
        testTransaction_RevertWhen_WhenTargetIsEntryPoint_WhenHandleOps_WhenBeneficiaryIsNotSender();
        // testTransaction_WhenTargetIsEntryPoint_WhenHandleAggregatedOps_WhenBeneficiaryIsSender(); // FIXME
        // testTransaction_RevertWhen_WhenTargetIsEntryPoint_WhenHandleAggregatedOps_WhenBeneficiaryIsNotSender();

        // paymaster tests
        // testTransaction_RevertWhen_TargetIsPaymaster_WhenWithdrawTo(); // FIXME!!
        // testTransaction_RevertWhen_TargetIsPaymaster_WhenDeposit(); // FIXME!!
    }

    function testAssertSelectors() public {
        assertEq(bytes4(keccak256("withdrawTo(address,uint256)")), bytes4(0x205c2878));
        assertEq(bytes4(keccak256("withdrawStake(address)")), bytes4(0xc23a5cea));
        assertEq(
            bytes4(
                keccak256(
                    "handleOps((address,uint256,bytes,bytes,uint256,uint256,uint256,uint256,uint256,bytes,bytes)[],address)"
                )
            ),
            bytes4(0x1fad948c)
        );
        assertEq(
            bytes4(
                keccak256(
                    "handleAggregatedOps(((address,uint256,bytes,bytes,uint256,uint256,uint256,uint256,uint256,bytes,bytes)[],address,bytes)[],address)"
                )
            ),
            bytes4(0x4b1d7cf5)
        );
        assertEq(bytes4(keccak256("deposit()")), bytes4(0xd0e30db0));
    }

    function testTransaction_RevertWhen_ContractDeployment() public {
        // deploy contract directly from EOA
        // should revert at Geth level with ...is trying to create a contract directly...
        vm.broadcast(senderPk);
        new Counter();
    }

    function testTransaction_WhenTargetIsAllowed() public view {
        // call allowed targets
        // should work at Geth level
        _entryPoint.walletFactory();
        _kintoID.lastMonitoredAt();
        _factory.beacon();
        _paymaster.appRegistry();
    }

    /* ============ EntryPoint: Withdraw To tests ============ */

    function testTransaction_WhenTargetIsEntryPoint_WhenWithdrawTo_WhenAddressIsSender() public {
        // call entrypoint.withdrawTo from sender with sender as `withdrawAddress`
        // should work at Geth level and revert at contract level
        vm.expectRevert("Withdraw amount too large");
        vm.broadcast(senderPk);
        _entryPoint.withdrawTo(payable(sender), 1 ether);
    }

    // FIXME
    function testTransaction_RevertWhen_WhenTargetIsEntryPoint_WhenWithdrawTo_WhenAddressIsNotSender() public {
        // call entrypoint.withdrawTo from sender with _user as `withdrawAddress`
        // should revert at GETH level with ...is trying to withdraw/withdrawStake from EntryPoint to a param different than the sender...
        console.log("Sender: ", sender);
        console.log("User: ", _user);
        console.log("msg.sender", msg.sender);
        console.log("this", address(this));
        vm.broadcast(senderPk);
        _entryPoint.withdrawTo(_user, 1 ether);
    }

    /* ============ EntryPoint: Withdraw Stake tests ============ */

    function testTransaction_WhenTargetIsEntryPoint_WhenWithdrawStake_WhenAddressIsSender() public {
        // call entrypoint.withdrawStake from this address with this as `withdrawAddress`
        vm.expectRevert("No stake to withdraw");
        vm.broadcast(senderPk);
        _entryPoint.withdrawStake(payable(payable(sender)));
    }

    function testTransaction_RevertWhen_WhenTargetIsEntryPoint_WhenWithdrawStake_WhenAddressIsNotSender() public {
        // call entrypoint.withdrawStake from this address with this as `withdrawAddress`
        // should revert at GETH level with ...is trying to withdraw/withdrawStake from EntryPoint to a param different than the sender...
        vm.expectRevert();
        _entryPoint.withdrawStake(_user);
    }

    /* ============ EntryPoint: Handle Ops tests ============ */
    event BeforeExecution();
    // FIXME!!

    function testTransaction_WhenTargetIsEntryPoint_WhenHandleOps_WhenBeneficiaryIsSender() public {
        UserOperation[] memory userOps = new UserOperation[](0);
        // call entrypoint.handleOps from sender with sender as `beneficiary`
        // should work and emit BeforeExecution event
        // vm.expectEmit();
        // emit BeforeExecution();
        vm.broadcast(senderPk);
        _entryPoint.handleOps(userOps, payable(sender));
    }

    function extractAddress(bytes memory data, uint256 offset) public pure returns (address) {
        require(data.length >= offset + 20, "Data does not contain a valid address");

        address extractedAddress;
        assembly {
            // Load 20 bytes of data from the specified offset into the extractedAddress variable
            extractedAddress := mload(add(add(data, 0x20), offset))
        }
        return extractedAddress;
    }

    function testTransaction_RevertWhen_WhenTargetIsEntryPoint_WhenHandleOps_WhenBeneficiaryIsNotSender() public {
        UserOperation[] memory userOps = new UserOperation[](2);
        // struct UserOperation {
        //     address sender;
        //     uint256 nonce;
        //     bytes initCode;
        //     bytes callData;
        //     uint256 callGasLimit;
        //     uint256 verificationGasLimit;
        //     uint256 preVerificationGas;
        //     uint256 maxFeePerGas;
        //     uint256 maxPriorityFeePerGas;
        //     bytes paymasterAndData;
        //     bytes signature;
        // }

        // [
        //     [
        //         "0x8dec08ed6392310a15fc140e4509e2be90eafe3c",
        //         "0",
        //         "0x",
        //         "0xb61d27f60000000000000000000000008dec08ed6392310a15fc140e4509e2be90eafe3c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000a4ca85f334000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000002000000000000000000000000edf966836862ebb5296732b347e9727bd993a652000000000000000000000000a4ab888b2fbc575b50ee947f66eb1f429dc6455800000000000000000000000000000000000000000000000000000000",
        //         "250000",
        //         "230000",
        //         "109999",
        //         "115000000",
        //         "0",
        //         "0x1842a4eff3efd24c50b63c3cf89cecee245fc2bd",
        //         "0x4dc07ead41882c378860967477698c71d252cb3ffdaa19499e1be2e669dc589f4652deee24a5c68bd50d8bae94f62d2fcc80ed00c124242cd4aec2a4b3d1b4041c"
        //     ]
        // ]

        userOps[0] = UserOperation(
            0x8Dec08ED6392310A15Fc140e4509E2bE90eafe3C,
            0,
            "0x",
            "0xb61d27f60000000000000000000000008dec08ed6392310a15fc140e4509e2be90eafe3c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000a4ca85f334000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000002000000000000000000000000edf966836862ebb5296732b347e9727bd993a652000000000000000000000000a4ab888b2fbc575b50ee947f66eb1f429dc6455800000000000000000000000000000000000000000000000000000000",
            250000,
            230000,
            109999,
            115000000,
            0,
            "0x1842a4eff3efd24c50b63c3cf89cecee245fc2bd",
            "0x4dc07ead41882c378860967477698c71d252cb3ffdaa19499e1be2e669dc589f4652deee24a5c68bd50d8bae94f62d2fcc80ed00c124242cd4aec2a4b3d1b4041c"
        );
        userOps[1] = UserOperation(
            0x8Dec08ED6392310A15Fc140e4509E2bE90eafe3C,
            0,
            "0x",
            "0xb61d27f60000000000000000000000008dec08ed6392310a15fc140e4509e2be90eafe3c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000a4ca85f334000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000002000000000000000000000000edf966836862ebb5296732b347e9727bd993a652000000000000000000000000a4ab888b2fbc575b50ee947f66eb1f429dc6455800000000000000000000000000000000000000000000000000000000",
            250000,
            230000,
            109999,
            115000000,
            0,
            "0x1842a4eff3efd24c50b63c3cf89cecee245fc2bd",
            "0x4dc07ead41882c378860967477698c71d252cb3ffdaa19499e1be2e669dc589f4652deee24a5c68bd50d8bae94f62d2fcc80ed00c124242cd4aec2a4b3d1b4041c"
        );

        bytes memory handleOpsHex =
            hex"1fad948c0000000000000000000000000000000000000000000000000000000000000040000000000000000000000000433704c40f80cbff02e86fd36bc8bac5e31eb0c1000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000200000000000000000000000008dec08ed6392310a15fc140e4509e2be90eafe3c000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001600000000000000000000000000000000000000000000000000000000000000180000000000000000000000000000000000000000000000000000000000003d0900000000000000000000000000000000000000000000000000000000000038270000000000000000000000000000000000000000000000000000000000001adaf0000000000000000000000000000000000000000000000000000000006dac2c000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000300000000000000000000000000000000000000000000000000000000000000034000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000144b61d27f60000000000000000000000008dec08ed6392310a15fc140e4509e2be90eafe3c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000a4ca85f334000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000002000000000000000000000000edf966836862ebb5296732b347e9727bd993a652000000000000000000000000a4ab888b2fbc575b50ee947f66eb1f429dc64558000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000141842a4eff3efd24c50b63c3cf89cecee245fc2bd00000000000000000000000000000000000000000000000000000000000000000000000000000000000000414dc07ead41882c378860967477698c71d252cb3ffdaa19499e1be2e669dc589f4652deee24a5c68bd50d8bae94f62d2fcc80ed00c124242cd4aec2a4b3d1b4041c00000000000000000000000000000000000000000000000000000000000000";
        address beneficiary = extractAddress(handleOpsHex, 4 + 64); // selector + dynamic sized array
        // console.log("Beneficiary: ", beneficiary == userOps[0].sender);
        console.logBytes(abi.encodeWithSelector(_entryPoint.handleOps.selector, userOps, payable(sender)));
        console.log("SENDER", sender);
        // console.logBytes(handleOpsHex);

        // // call entrypoint.handleOps from sender with _user as `beneficiary`
        // // should revert at GETH level with ...is trying to handleOps/handleAggregatedOps from EntryPoint to a beneficiary different than the sender...
        // vm.broadcast(senderPk);
        // _entryPoint.handleOps(userOps, payable(_user));
    }

    // /* ============ EntryPoint: Handle Aggreated Ops tests ============ */

    function testTransaction_WhenTargetIsEntryPoint_WhenHandleAggregatedOps_WhenBeneficiaryIsSender() public {
        IEntryPoint.UserOpsPerAggregator[] memory userOpsPerAggregator = new IEntryPoint.UserOpsPerAggregator[](1);
        // call entrypoint.handleAggregatedOps from sender with sender as `beneficiary`
        // should work and emit BeforeExecution event
        // vm.expectEmit();
        // emit BeforeExecution();
        console.logBytes(
            abi.encodeWithSelector(_entryPoint.handleAggregatedOps.selector, userOpsPerAggregator, payable(sender))
        );

        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = UserOperation(
            0x8Dec08ED6392310A15Fc140e4509E2bE90eafe3C,
            0,
            "0x",
            "0xb61d27f60000000000000000000000008dec08ed6392310a15fc140e4509e2be90eafe3c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000a4ca85f334000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000002000000000000000000000000edf966836862ebb5296732b347e9727bd993a652000000000000000000000000a4ab888b2fbc575b50ee947f66eb1f429dc6455800000000000000000000000000000000000000000000000000000000",
            250000,
            230000,
            109999,
            115000000,
            0,
            "0x1842a4eff3efd24c50b63c3cf89cecee245fc2bd",
            "0x4dc07ead41882c378860967477698c71d252cb3ffdaa19499e1be2e669dc589f4652deee24a5c68bd50d8bae94f62d2fcc80ed00c124242cd4aec2a4b3d1b4041c"
        );

        userOpsPerAggregator[0] = IEntryPoint.UserOpsPerAggregator(userOps, IAggregator(address(123)), new bytes(0));
        console.logBytes(
            abi.encodeWithSelector(_entryPoint.handleAggregatedOps.selector, userOpsPerAggregator, payable(sender))
        );

        vm.broadcast(senderPk);
        _entryPoint.handleAggregatedOps(userOpsPerAggregator, payable(sender));
    }

    function testTransaction_RevertWhen_WhenTargetIsEntryPoint_WhenHandleAggregatedOps_WhenBeneficiaryIsNotSender()
        public
    {
        IEntryPoint.UserOpsPerAggregator[] memory userOpsPerAggregator = new IEntryPoint.UserOpsPerAggregator[](0);

        // call entrypoint.handleAggregatedOps from sender with _user as `beneficiary`
        // should revert at GETH level with ...is trying to handleOps/handleAggregatedOps from EntryPoint to a beneficiary different than the sender...
        vm.broadcast(senderPk);
        _entryPoint.handleAggregatedOps(userOpsPerAggregator, payable(_user));
    }

    /* ============ Paymaster tests ============ */

    function testTransaction_RevertWhen_TargetIsPaymaster_WhenWithdrawTo() public {
        // call paymaster.withdrawTo
        // should revert at GETH level with ...SponsorPaymaster withDrawTo() and deposit() are not allowed...
        vm.broadcast(senderPk);
        _paymaster.withdrawTo(payable(sender), 1 ether);
    }

    function testTransaction_RevertWhen_TargetIsPaymaster_WhenDeposit() public {
        // call paymaster.deposit
        // should revert at GETH level with ...SponsorPaymaster withDrawTo() and deposit() are not allowed...
        vm.broadcast(senderPk);
        _paymaster.deposit();
    }

    receive() external payable {}
}
