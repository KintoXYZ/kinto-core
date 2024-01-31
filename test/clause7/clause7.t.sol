// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@aa/interfaces/IAggregator.sol";

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../SharedSetup.t.sol";

contract Clause7thTest is SharedSetup {
    uint256 public constant KINTO_RULES_BLOCK_START = 100;
    mapping(address => mapping(bytes4 => bool)) public allowedFunctions;

    function setUp() public override {
        super.setUp();
        vm.roll(KINTO_RULES_BLOCK_START);
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
        // deploy contract
        vm.expectRevert();
        new Counter();
    }

    function testTransaction_WhenTargetIsAllowed() public {
        // call allowed targets
        _entryPoint.walletFactory();
        _kintoID.lastMonitoredAt();
        _walletFactory.beacon();
        _paymaster.appRegistry();
    }

    function testTransaction_RevertWhen_WhenTargetIsNotAllowed() public {
        address counterAddr =
            _walletFactory.deployContract(_owner, 0, abi.encodePacked(type(Counter).creationCode), bytes32(0));

        // call not allowed targets
        vm.expectRevert();
        Counter(counterAddr).increment();
    }

    /* ============ EntryPoint: Withdraw To tests ============ */

    function testTransaction_WhenTargetIsEntryPoint_WhenWithdrawTo_WhenAddressIsSender() public {
        vm.deal(address(this), 1 ether);
        _entryPoint.depositTo{value: 1 ether}(address(this));

        // call entrypoint.withdrawTo from this address with this as `withdrawAddress`
        _entryPoint.withdrawTo(payable(address(this)), 1 ether);
    }

    function testTransaction_RevertWhen_WhenTargetIsEntryPoint_WhenWithdrawTo_WhenAddressIsNotSender() public {
        vm.deal(address(this), 1 ether);
        _entryPoint.depositTo{value: 1 ether}(address(this));

        // call entrypoint.withdrawTo from this address with this as `withdrawAddress`
        vm.expectRevert();
        _entryPoint.withdrawTo(_user, 1 ether);
    }

    /* ============ EntryPoint: Withdraw Stake tests ============ */

    function testTransaction_WhenTargetIsEntryPoint_WhenWithdrawStake_WhenAddressIsSender() public {
        vm.deal(address(this), 1 ether);

        // add & unlock stake
        _entryPoint.addStake{value: 1 ether}(1);
        _entryPoint.unlockStake();

        vm.warp(block.timestamp + 1);

        // call entrypoint.withdrawStake from this address with this as `withdrawAddress`
        vm.prank(address(this));
        _entryPoint.withdrawStake(payable(address(this)));
    }

    function testTransaction_RevertWhen_WhenTargetIsEntryPoint_WhenWithdrawStake_WhenAddressIsNotSender() public {
        vm.deal(address(this), 1 ether);

        // add & unlock stake
        _entryPoint.addStake{value: 1 ether}(1);
        _entryPoint.unlockStake();

        vm.warp(block.timestamp + 1);

        // call entrypoint.withdrawStake from this address with this as `withdrawAddress`
        vm.expectRevert();
        vm.prank(address(this));
        _entryPoint.withdrawStake(_user);
    }

    /* ============ EntryPoint: Handle Ops tests ============ */

    function testTransaction_WhenTargetIsEntryPoint_WhenHandleOps_WhenBeneficiaryIsSender() public {
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = _createUserOperation(
            address(_kintoWallet),
            address(counter),
            _kintoWallet.getNonce(),
            privateKeys,
            abi.encodeWithSignature("increment()"),
            address(_paymaster)
        );

        // call entrypoint.handleOps from this address with this as `beneficiary`
        _entryPoint.handleOps(userOps, payable(address(this)));
        assertEq(counter.count(), 1);
    }

    function testTransaction_RevertWhen_WhenTargetIsEntryPoint_WhenHandleOps_WhenBeneficiaryIsNotSender() public {
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = _createUserOperation(
            address(_kintoWallet),
            address(counter),
            _kintoWallet.getNonce(),
            privateKeys,
            abi.encodeWithSignature("increment()"),
            address(_paymaster)
        );

        // call entrypoint.handleOps from this address with _user as `beneficiary`
        vm.expectRevert();
        _entryPoint.handleOps(userOps, payable(_user));
    }

    /* ============ EntryPoint: Handle Aggreated Ops tests ============ */

    function testTransaction_WhenTargetIsEntryPoint_WhenHandleAggregatedOps_WhenBeneficiaryIsSender() public {
        IEntryPoint.UserOpsPerAggregator[] memory userOpsPerAggregator = new IEntryPoint.UserOpsPerAggregator[](1);
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = _createUserOperation(
            address(_kintoWallet),
            address(counter),
            _kintoWallet.getNonce(),
            privateKeys,
            abi.encodeWithSignature("increment()"),
            address(_paymaster)
        );
        userOpsPerAggregator[0] = IEntryPoint.UserOpsPerAggregator(
            userOps,
            IAggregator(address(123)), // aggregator address
            bytes("") // we don't care about signature
        );

        // @dev since we don't have yet support for aggregated signatures, we assert that it revert because the signature
        // is not valid (which means that it has passed the GETH level check)
        // call entrypoint.handleAggregatedOps from this address with this as `beneficiary`
        vm.expectRevert(abi.encodeWithSelector(IEntryPoint.SignatureValidationFailed.selector, address(123)));
        _entryPoint.handleAggregatedOps(userOpsPerAggregator, payable(address(this)));
    }

    function testTransaction_RevertWhen_WhenTargetIsEntryPoint_WhenHandleAggregatedOps_WhenBeneficiaryIsNotSender()
        public
    {
        IEntryPoint.UserOpsPerAggregator[] memory userOpsPerAggregator = new IEntryPoint.UserOpsPerAggregator[](1);
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = _createUserOperation(
            address(_kintoWallet),
            address(counter),
            _kintoWallet.getNonce(),
            privateKeys,
            abi.encodeWithSignature("increment()"),
            address(_paymaster)
        );
        userOpsPerAggregator[0] = IEntryPoint.UserOpsPerAggregator(
            userOps,
            IAggregator(address(_kintoWallet)),
            bytes("") // we don't care about signature
        );

        // @dev it should revert at the GETH level and not because the signature is not valid
        // call entrypoint.handleAggregatedOps from this address with this as `beneficiary`
        vm.expectRevert();
        _entryPoint.handleAggregatedOps(userOpsPerAggregator, payable(address(this)));
    }

    /* ============ Paymaster tests ============ */

    function testTransaction_RevertWhen_TargetIsPaymaster_WhenWithdrawTo() public {
        // call paymaster.withdrawTo
        vm.expectRevert();
        _paymaster.withdrawTo(_user, 1 ether);
    }

    function testTransaction_RevertWhen_TargetIsPaymaster_WhenDeposit() public {
        // call paymaster.deposit
        vm.expectRevert();
        _paymaster.deposit();
    }

    receive() external payable {}
}
