// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "@aa/interfaces/IEntryPoint.sol";
import "@aa/core/EntryPoint.sol";

import "@kinto-core/apps/KintoAppRegistry.sol";
import "@kinto-core/paymasters/SponsorPaymaster.sol";
import "@kinto-core/sample/Counter.sol";
import "@kinto-core/interfaces/IKintoWallet.sol";
import {IKintoWalletFactory} from "@kinto-core/interfaces/IKintoWalletFactory.sol";

import "@kinto-core-test/SharedSetup.t.sol";

contract SponsorPaymasterUpgrade is SponsorPaymaster {
    constructor(IEntryPoint __entryPoint, IKintoWalletFactory factory, address _owner)
        SponsorPaymaster(__entryPoint, factory)
    {
        _disableInitializers();
        _transferOwnership(_owner);
    }

    function newFunction() public pure returns (uint256) {
        return 1;
    }
}

contract SponsorPaymasterTest is SharedSetup {
    function setUp() public override {
        super.setUp();
        vm.deal(_user, 1e20);
    }

    function testUp() public override {
        super.testUp();
        assertEq(_paymaster.COST_OF_POST(), 200_000);
        assertEq(_paymaster.userOpMaxCost(), 0.03 ether);
    }

    /* ============ Events ============ */

    event AppRegistrySet(address oldRegistry, address newRegistry);
    event UserOpMaxCostSet(uint256 oldUserOpMaxCost, uint256 newUserOpMaxCost);

    function testUpgradeTo() public {
        SponsorPaymasterUpgrade _newImplementation = new SponsorPaymasterUpgrade(_entryPoint, _walletFactory, _owner);

        vm.prank(_owner);
        _paymaster.upgradeTo(address(_newImplementation));

        _newImplementation = SponsorPaymasterUpgrade(address(_paymaster));
        assertEq(_newImplementation.newFunction(), 1);
    }

    function testUpgradeTo_RevertWhen_CallerIsNotOwner() public {
        vm.expectRevert(ISponsorPaymaster.OnlyOwner.selector);
        _paymaster.upgradeTo(address(this));
    }

    /* ============ addDepositFor ============ */

    function testAddDepositFor_WhenWallet() public {
        uint256 amount = 1e18;
        vm.deal(address(_kintoWallet), amount);
        uint256 balance = address(_kintoWallet).balance;

        vm.prank(address(_kintoWallet));
        _paymaster.addDepositFor{value: amount}(address(_owner));

        assertEq(address(_kintoWallet).balance, balance - amount);
        assertEq(_paymaster.balances(_owner), amount);
    }

    function testAddDepositFor_WhenAccountIsEOA_WhenAccountIsKYCd() public {
        uint256 balance = address(_owner).balance;
        vm.prank(_owner);
        _paymaster.addDepositFor{value: 5e18}(address(_owner));
        assertEq(address(_owner).balance, balance - 5e18);
        assertEq(_paymaster.balances(_owner), 5e18);
    }

    function testAddDepositFor_WhenAccountIsContract() public {
        uint256 balance = address(_owner).balance;
        vm.prank(_owner);
        _paymaster.addDepositFor{value: 5e18}(address(_owner));
        assertEq(address(_owner).balance, balance - 5e18);
        assertEq(_paymaster.balances(_owner), 5e18);
    }

    function testAddDepositFor_RevertWhen_ZeroValue() public {
        vm.expectRevert(ISponsorPaymaster.InvalidAmount.selector);
        vm.prank(_owner);
        _paymaster.addDepositFor{value: 0}(address(_owner));
    }

    function testAddDepositFor_RevertWhen_SenderIsNotKYCd() public {
        assertEq(_kintoID.isKYC(address(_user)), false);
        vm.expectRevert(ISponsorPaymaster.SenderKYCRequired.selector);
        vm.prank(_user);
        _paymaster.addDepositFor{value: 5e18}(address(_user));
    }

    function testAddDepositFor_RevertWhen_AccountIsEOA_WhenAccountIsNotKYCd() public {
        assertEq(_kintoID.isKYC(address(_user)), false);
        vm.expectRevert(ISponsorPaymaster.AccountKYCRequired.selector);
        vm.prank(_owner);
        _paymaster.addDepositFor{value: 5e18}(address(_user));
    }

    /* ============ withdrawTokensTo ============ */

    function testWithdrawTokensTo(uint256 someonePk) public {
        // ensure the private key is within the valid range for Ethereum
        vm.assume(someonePk > 0 && someonePk < SECP256K1_MAX_PRIVATE_KEY);
        address someone = vm.addr(someonePk);
        vm.assume(someone.code.length == 0); // assume someone is an EOA
        vm.assume(someone != address(0)); // assume someone is not the zero address

        // add some balance
        vm.deal(someone, 10 ether);

        // user must be KYC'd (skip owner since it's already KYC'd)
        if (someone != _owner) approveKYC(_kycProvider, someone, someonePk);

        uint256 balance = address(someone).balance;

        vm.startPrank(someone);

        _paymaster.addDepositFor{value: 5 ether}(address(someone));
        assertEq(address(someone).balance, balance - 5 ether);

        _paymaster.unlockTokenDeposit();
        vm.roll(block.number + 1); // advance block to allow withdraw

        _paymaster.withdrawTokensTo(address(someone), 5 ether);
        assertEq(address(someone).balance, balance);

        vm.stopPrank();
    }

    function testWithdrawTokensTo_WhenWithdraingToOtherAddress() public {
        uint256 someonePk = 123;
        address someone = vm.addr(someonePk);

        vm.assume(someone.code.length == 0); // assume someone is an EOA
        vm.assume(someone != address(0) && someone != _user); // assume someone is not the zero address and not the _user

        // add some balance
        vm.deal(someone, 10 ether);

        // user must be KYC'd (skip owner since it's already KYC'd)
        if (someone != _owner) approveKYC(_kycProvider, someone, someonePk);

        uint256 someoneBalance = address(someone).balance;
        uint256 userBalance = address(_user).balance;

        vm.startPrank(someone);

        _paymaster.addDepositFor{value: 5 ether}(address(someone));
        assertEq(address(someone).balance, someoneBalance - 5 ether);

        _paymaster.unlockTokenDeposit();
        vm.roll(block.number + 1); // advance block to allow withdraw

        // withdraw tokens to _user
        _paymaster.withdrawTokensTo(address(_user), 5 ether);
        assertEq(address(someone).balance, someoneBalance - 5 ether);
        assertEq(address(_user).balance, userBalance + 5 ether);

        vm.stopPrank();
    }

    function testWithdrawTokensTo_RevertWhen_DepositLocked() public {
        approveKYC(_kycProvider, _user, _userPk);
        uint256 balance = _user.balance;

        vm.prank(_user);
        _paymaster.addDepositFor{value: 5e18}(_user);
        assertEq(_user.balance, balance - 5e18);

        // user withdraws 5 eth
        vm.expectRevert(ISponsorPaymaster.TokenDepositLocked.selector);
        vm.prank(_user);
        _paymaster.withdrawTokensTo(_user, 5e18);

        assertEq(_user.balance, balance - 5e18);
    }

    function testWithdrawTokensTo_RevertWhen_TargetIsZeroAddress() public {
        vm.prank(_owner);
        _paymaster.addDepositFor{value: 5e18}(_owner);

        vm.prank(_owner);
        _paymaster.unlockTokenDeposit();
        vm.roll(block.number + 1); // advance block to allow withdraw

        // _owner withdraws 5 eth
        vm.expectRevert(ISponsorPaymaster.InvalidTarget.selector);
        vm.prank(_owner);
        _paymaster.withdrawTokensTo(address(0), 5e18);
    }

    function testWithdrawTokensTo_RevertWhen_TargetIsContract() public {
        vm.prank(_owner);
        _paymaster.addDepositFor{value: 5e18}(_owner);

        vm.prank(_owner);
        _paymaster.unlockTokenDeposit();
        vm.roll(block.number + 1); // advance block to allow withdraw

        // _owner withdraws 5 eth
        vm.expectRevert(ISponsorPaymaster.InvalidTarget.selector);
        vm.prank(_owner);
        _paymaster.withdrawTokensTo(address(_entryPoint), 5e18);
    }

    /* ============ depositInfo ============ */

    function testDepositInfo_WhenCallerDepositsToHimself() public {
        vm.prank(_owner);
        _paymaster.addDepositFor{value: 5e18}(address(_owner));
        (uint256 amount, uint256 _unlockBlock) = _paymaster.depositInfo(address(_owner));
        assertEq(amount, 5e18);
        assertEq(_unlockBlock, 0);
    }

    function testDepositInfo_WhenCallerDepositsToSomeoneElse() public {
        approveKYC(_kycProvider, _user, _userPk);
        vm.prank(_owner);
        _paymaster.addDepositFor{value: 5e18}(address(_user));

        (uint256 amount, uint256 _unlockBlock) = _paymaster.depositInfo(address(_user));
        assertEq(amount, 5e18);
        assertEq(_unlockBlock, 0);
    }

    /* ============ Per-Op: Global Rate limits ============ */

    function testValidatePaymasterUserOp() public {
        UserOperation memory userOp = _createUserOperation(
            address(_kintoWallet),
            address(_kintoWallet),
            _kintoWallet.getNonce(),
            privateKeys,
            abi.encodeWithSignature("increment()"),
            address(_paymaster)
        );

        vm.prank(address(_entryPoint));
        _paymaster.validatePaymasterUserOp(userOp, "", 0);
    }

    function testValidatePaymasterUserOp_RevertWhen_GasLimitIsLessThanCostOfPost() public {
        UserOperation memory userOp = _createUserOperation(
            address(_kintoWallet),
            address(_kintoWallet),
            _kintoWallet.getNonce(),
            privateKeys,
            abi.encodeWithSignature("increment()"),
            address(_paymaster)
        );

        // verificationGasLimit is 1 less than COST_OF_POST
        userOp.verificationGasLimit = _paymaster.COST_OF_POST() - 1;

        vm.prank(address(_entryPoint));
        vm.expectRevert(ISponsorPaymaster.GasOutsideRangeForPostOp.selector);
        _paymaster.validatePaymasterUserOp(userOp, "", 0);
    }

    function testValidatePaymasterUserOp_RevertWhen_GasLimitIsMoreThanCostOfVerification() public {
        UserOperation memory userOp = _createUserOperation(
            address(_kintoWallet),
            address(_kintoWallet),
            _kintoWallet.getNonce(),
            privateKeys,
            abi.encodeWithSignature("increment()"),
            address(_paymaster)
        );

        // verificationGasLimit is 1 more than COST_OF_POST
        userOp.verificationGasLimit = _paymaster.MAX_COST_OF_VERIFICATION() + 1;

        vm.prank(address(_entryPoint));
        vm.expectRevert(ISponsorPaymaster.GasOutsideRangeForPostOp.selector);
        _paymaster.validatePaymasterUserOp(userOp, "", 0);
    }

    function testValidatePaymasterUserOp_RevertWhen_PreGasLimitIsMoreThanMaxPreVerification() public {
        UserOperation memory userOp = _createUserOperation(
            address(_kintoWallet),
            address(_kintoWallet),
            _kintoWallet.getNonce(),
            privateKeys,
            abi.encodeWithSignature("increment()"),
            address(_paymaster)
        );

        // preVerificationGas is 1 more than MAX_COST_OF_PREVERIFICATION
        userOp.preVerificationGas = _paymaster.MAX_COST_OF_PREVERIFICATION() + 1;

        vm.prank(address(_entryPoint));
        vm.expectRevert(ISponsorPaymaster.GasTooHighForVerification.selector);
        _paymaster.validatePaymasterUserOp(userOp, "", 0);
    }

    function testValidatePaymasterUserOp_RevertWhen_PaymasterAndDataIsNotLength20() public {
        UserOperation memory userOp = _createUserOperation(
            address(_kintoWallet),
            address(_kintoWallet),
            _kintoWallet.getNonce(),
            privateKeys,
            abi.encodeWithSignature("increment()"),
            address(_paymaster)
        );

        // paymasterAndData is 21 bytes
        userOp.paymasterAndData = new bytes(21);

        vm.prank(address(_entryPoint));
        vm.expectRevert(ISponsorPaymaster.PaymasterAndDataLengthInvalid.selector);
        _paymaster.validatePaymasterUserOp(userOp, "", 0);
    }

    function testValidatePaymasterUserOp_RevertWhen_GasIsTooHigh() public {
        UserOperation memory userOp = _createUserOperation(
            address(_kintoWallet),
            address(_kintoWallet),
            _kintoWallet.getNonce(),
            privateKeys,
            abi.encodeWithSignature("increment()"),
            address(_paymaster)
        );

        // gas price set to 100 ether
        userOp.maxFeePerGas = 100 ether;
        userOp.maxPriorityFeePerGas = 100 ether;

        vm.prank(address(_entryPoint));
        vm.expectRevert(ISponsorPaymaster.GasTooHighForUserOp.selector);
        _paymaster.validatePaymasterUserOp(userOp, "", 0);
    }

    /* ============ Global Rate limits (tx & batched ops rates) ============ */

    function testAppLimits() public {
        (uint256 operationCount, uint256 lastOperationTime, uint256 ethCostCount, uint256 costLimitLastOperationTime) =
            _paymaster.appUserLimit(address(_kintoWallet), address(counter));
        assertTrue(operationCount == 0);
        assertTrue(lastOperationTime == 0);
        assertTrue(ethCostCount == 0);
        assertTrue(costLimitLastOperationTime == 0);

        uint256[4] memory appLimits = _kintoAppRegistry.getContractLimits(address(counter));
        _incrementCounterTxs(appLimits[1] - 1, address(counter));

        // move time to GAS_LIMIT_PERIOD + 1 and call monitor so we keep the isKYC active
        vm.warp(block.timestamp + appLimits[2] + 1);
        address[] memory users = new address[](1);
        users[0] = _user;
        IKintoID.MonitorUpdateData[][] memory updates = new IKintoID.MonitorUpdateData[][](1);
        updates[0] = new IKintoID.MonitorUpdateData[](1);
        updates[0][0] = IKintoID.MonitorUpdateData(true, true, 5);
        vm.prank(_kycProvider);
        _kintoID.monitor(users, updates);

        // increment one more time
        _incrementCounterTxs(1, address(counter));

        // check limits
        (operationCount, lastOperationTime, ethCostCount, costLimitLastOperationTime) =
            _paymaster.appUserLimit(address(_kintoWallet), address(counter));
        assertTrue(operationCount > 0);
        assertEq(lastOperationTime, block.timestamp);
        assertTrue(ethCostCount > 0);
        assertEq(costLimitLastOperationTime, block.timestamp);
    }

    function testValidatePaymasterUserOp_WithinTxRateLimit() public {
        // fixme: once _setOperationCount works fine, refactor and use _setOperationCount;

        // create app with app limits higher than the global ones so we assert that the global is the one that is used in the test
        uint256[4] memory appLimits = [
            _paymaster.RATE_LIMIT_PERIOD() + 1,
            _paymaster.RATE_LIMIT_THRESHOLD_TOTAL() + 1,
            GAS_LIMIT_PERIOD,
            GAS_LIMIT_THRESHOLD
        ];
        updateMetadata(address(_kintoWallet), "counter", address(counter), appLimits, new address[](0));

        // execute transactions (with one user op per tx) one by one until reaching the threshold
        _incrementCounterTxs(_paymaster.RATE_LIMIT_THRESHOLD_TOTAL(), address(counter));

        // reset period
        vm.warp(block.timestamp + _paymaster.RATE_LIMIT_PERIOD() + 1);

        // can again execute as many transactions as the threshold allows
        _incrementCounterTxs(_paymaster.RATE_LIMIT_THRESHOLD_TOTAL(), address(counter));
    }

    function testValidatePaymasterUserOp_RevertWhen_TxRateLimitExceeded() public {
        // fixme: once _setOperationCount works fine, refactor and use _setOperationCount;

        // create app with app limits higher than the global ones so we assert that the global is the one that is used in the test
        uint256[4] memory appLimits = [
            _paymaster.RATE_LIMIT_PERIOD() + 1,
            _paymaster.RATE_LIMIT_THRESHOLD_TOTAL() + 1,
            GAS_LIMIT_PERIOD,
            GAS_LIMIT_THRESHOLD
        ];
        updateMetadata(address(_kintoWallet), "counter", address(counter), appLimits, new address[](0));

        // execute transactions (with one user op per tx) one by one until reaching the threshold
        _incrementCounterTxs(_paymaster.RATE_LIMIT_THRESHOLD_TOTAL(), address(counter));

        // execute one more op and assert that it reverts
        UserOperation[] memory userOps = _incrementCounterOps(1, address(counter));
        vm.expectEmit(true, true, true, false);
        uint256 last = userOps.length - 1;
        emit PostOpRevertReason(
            _entryPoint.getUserOpHash(userOps[last]), userOps[last].sender, userOps[last].nonce, bytes("")
        );
        vm.recordLogs();
        _entryPoint.handleOps(userOps, payable(_owner));
        assertRevertReasonEq(abi.encodeWithSelector(ISponsorPaymaster.KintoRateLimitExceeded.selector));
    }

    function testValidatePaymasterUserOp_WithinOpsRateLimit() public {
        // fixme: once _setOperationCount works fine, refactor and use _setOperationCount;

        // create app with app limits higher than the global ones so we assert that the global is the one that is used in the test
        uint256[4] memory appLimits = [
            _paymaster.RATE_LIMIT_PERIOD() + 1,
            _paymaster.RATE_LIMIT_THRESHOLD_TOTAL() + 1,
            GAS_LIMIT_PERIOD,
            GAS_LIMIT_THRESHOLD
        ];
        updateMetadata(address(_kintoWallet), "counter", address(counter), appLimits, new address[](0));

        // generate ops until reaching the threshold
        UserOperation[] memory userOps = _incrementCounterOps(_paymaster.RATE_LIMIT_THRESHOLD_TOTAL(), address(counter));
        _entryPoint.handleOps(userOps, payable(_owner));
    }

    function testValidatePaymasterUserOp_RevertWhen_OpsRateLimitExceeded() public {
        // fixme: once _setOperationCount works fine, refactor and use _setOperationCount;

        // create app with app limits higher than the global ones so we assert that the global is the one that is used in the test
        uint256[4] memory appLimits = [
            _paymaster.RATE_LIMIT_PERIOD() + 1,
            _paymaster.RATE_LIMIT_THRESHOLD_TOTAL() + 1,
            GAS_LIMIT_PERIOD,
            GAS_LIMIT_THRESHOLD
        ];
        updateMetadata(address(_kintoWallet), "counter", address(counter), appLimits, new address[](0));

        // generate ops until reaching the threshold and assert that it reverts
        UserOperation[] memory userOps =
            _incrementCounterOps(_paymaster.RATE_LIMIT_THRESHOLD_TOTAL() + 1, address(counter));
        vm.expectEmit(true, true, true, false);
        uint256 last = userOps.length - 1;
        emit PostOpRevertReason(
            _entryPoint.getUserOpHash(userOps[last]), userOps[last].sender, userOps[last].nonce, bytes("")
        );
        vm.recordLogs();
        _entryPoint.handleOps(userOps, payable(_owner));
        assertRevertReasonEq(abi.encodeWithSelector(ISponsorPaymaster.KintoRateLimitExceeded.selector));
    }

    /* ============ App Rate limits (tx & batched ops rates) ============ */

    function testValidatePaymasterUserOp_WithinAppTxRateLimit() public {
        // fixme: once _setOperationCount works fine, refactor and use _setOperationCount;
        uint256[4] memory appLimits = _kintoAppRegistry.getContractLimits(address(counter));

        // execute transactions (with one user op per tx) one by one until reaching the threshold
        _incrementCounterTxs(appLimits[1], address(counter));
    }

    function testValidatePaymasterUserOp_RevertWhen_AppTxRateLimitExceeded() public {
        // fixme: once _setOperationCount works fine, refactor and use _setOperationCount;
        uint256[4] memory appLimits = _kintoAppRegistry.getContractLimits(address(counter));

        // execute transactions (with one user op per tx) one by one until reaching the threshold
        _incrementCounterTxs(appLimits[1], address(counter));

        // execute one more op and assert that it reverts
        UserOperation[] memory userOps = _incrementCounterOps(1, address(counter));
        vm.expectEmit(true, true, true, false);
        uint256 last = userOps.length - 1;
        emit PostOpRevertReason(
            _entryPoint.getUserOpHash(userOps[last]), userOps[last].sender, userOps[last].nonce, bytes("")
        );
        vm.recordLogs();
        _entryPoint.handleOps(userOps, payable(_owner));
        assertRevertReasonEq(abi.encodeWithSelector(ISponsorPaymaster.AppRateLimitExceeded.selector));
    }

    function testValidatePaymasterUserOp_WithinAppOpsRateLimit() public {
        // fixme: once _setOperationCount works fine, refactor and use _setOperationCount;
        uint256[4] memory appLimits = _kintoAppRegistry.getContractLimits(address(counter));

        // generate ops until reaching the threshold
        UserOperation[] memory userOps = _incrementCounterOps(appLimits[1], address(counter));
        _entryPoint.handleOps(userOps, payable(_owner));
    }

    function testValidatePaymasterUserOp_RevertWhen_AppOpsRateLimitExceeded() public {
        // fixme: once _setOperationCount works fine, refactor and use _setOperationCount;
        uint256[4] memory appLimits = _kintoAppRegistry.getContractLimits(address(counter));

        // generate ops until reaching the threshold and assert that it reverts
        UserOperation[] memory userOps = _incrementCounterOps(appLimits[1] + 1, address(counter));
        vm.expectEmit(true, true, true, false);
        uint256 last = userOps.length - 1;
        emit PostOpRevertReason(
            _entryPoint.getUserOpHash(userOps[last]), userOps[last].sender, userOps[last].nonce, bytes("")
        );
        vm.recordLogs();
        _entryPoint.handleOps(userOps, payable(_owner));
        assertRevertReasonEq(abi.encodeWithSelector(ISponsorPaymaster.AppRateLimitExceeded.selector));
    }

    /* ============ App Gas limits  (tx & batched ops rates) ============ */

    function testValidatePaymasterUserOp_RevertWhen_AppTxGasLimitExceeded() public {
        /// fixme: once _setOperationCount works fine, refactor and use _setOperationCount;
        /// @dev create app with high app limits and low gas limit so we assert that the one used
        // in the test is the gas limit
        uint256[4] memory appLimits = [100e18, 100e18, GAS_LIMIT_PERIOD, 1 wei];
        updateMetadata(address(_kintoWallet), "counter", address(counter), appLimits, new address[](0));

        // execute transactions (with one user op per tx) one by one until reaching the gas limit
        _incrementCounterTxsUntilGasLimit(address(counter));

        // execute one more op and assert that it reverts
        UserOperation[] memory userOps = _incrementCounterOps(1, address(counter));
        vm.expectEmit(true, true, true, false);
        emit PostOpRevertReason(_entryPoint.getUserOpHash(userOps[0]), userOps[0].sender, userOps[0].nonce, bytes(""));
        vm.recordLogs();
        _entryPoint.handleOps(userOps, payable(_owner));
        assertRevertReasonEq(abi.encodeWithSelector(ISponsorPaymaster.AppGasLimitExceeded.selector));
    }

    function testValidatePaymasterUserOp_RevertWhen_AppOpsGasLimitExceeded() public {
        /// fixme: once _setOperationCount works fine, refactor and use _setOperationCount;
        /// @dev create app with high app limits and low gas limit so we assert that the one used
        // in the test is the gas limit
        uint256[4] memory appLimits = [100e18, 100e18, GAS_LIMIT_PERIOD, 1 wei];
        updateMetadata(address(_kintoWallet), "counter", address(counter), appLimits, new address[](0));

        // execute transactions until reaching gas limit and save the amount of apps that reached the threshold
        uint256 amt = _incrementCounterTxsUntilGasLimit(address(counter));

        // reset period
        // fixme: vm.warp(block.timestamp + _kintoAppRegistry.GAS_LIMIT_PERIOD() + 1);

        // generate `amt` ops until reaching the threshold and assert that it reverts
        UserOperation[] memory userOps = _incrementCounterOps(amt, address(counter));
        vm.expectEmit(true, true, true, false);
        uint256 last = userOps.length - 1;
        emit PostOpRevertReason(
            _entryPoint.getUserOpHash(userOps[last]), userOps[last].sender, userOps[last].nonce, bytes("")
        );
        vm.recordLogs();
        _entryPoint.handleOps(userOps, payable(_owner));
        assertRevertReasonEq(abi.encodeWithSelector(ISponsorPaymaster.AppGasLimitExceeded.selector));
    }

    function testSetAppRegistry() public {
        address oldAppRegistry = address(_kintoAppRegistry);
        address newAppRegistry = address(123);

        vm.expectEmit(true, true, true, true);
        emit AppRegistrySet(oldAppRegistry, newAppRegistry);

        vm.prank(_owner);
        _paymaster.setAppRegistry(newAppRegistry);
        assertEq(address(_paymaster.appRegistry()), newAppRegistry);
    }

    function testSetAppRegistry_RevertWhen_CallerIsNotOwner() public {
        vm.expectRevert("Ownable: caller is not the owner");
        _paymaster.setAppRegistry(address(123));
    }

    function testSetAppRegistry_RevertWhen_AddressIsZero() public {
        vm.expectRevert(ISponsorPaymaster.InvalidRegistry.selector);
        vm.prank(_owner);
        _paymaster.setAppRegistry(address(0));
    }

    function testSetAppRegistry_RevertWhen_SameAddress() public {
        vm.expectRevert(ISponsorPaymaster.InvalidRegistry.selector);
        vm.prank(_owner);
        _paymaster.setAppRegistry(address(_kintoAppRegistry));
    }

    function testUserOpMaxCost() public {
        uint256 oldUserOpMaxCost = _paymaster.userOpMaxCost();
        uint256 newUserOpMaxCost = 123;

        vm.expectEmit(true, true, true, true);
        emit UserOpMaxCostSet(oldUserOpMaxCost, newUserOpMaxCost);

        vm.prank(_owner);
        _paymaster.setUserOpMaxCost(newUserOpMaxCost);
        assertEq(_paymaster.userOpMaxCost(), newUserOpMaxCost);
    }

    function testUserOpMaxCost_RevertWhen_CallerIsNotOwner() public {
        vm.expectRevert("Ownable: caller is not the owner");
        _paymaster.setUserOpMaxCost(123);
    }

    // TODO:
    // reset gas limits after periods
    // test doing txs in different days

    /* ============ Helpers ============ */

    // fixme: somehow not working
    function _setOperationCount(SponsorPaymaster paymaster, address account, uint256 operationCount) internal {
        uint256 globalRateLimitSlot = 5; // slot number for the "globalRateLimit" mapping itself
        bytes32 globalRateLimitSlotHash = keccak256(abi.encode(account, globalRateLimitSlot)); // slot for the `operationCount` within the `RateLimitData` mapping.
        uint256 operationCountOffset = 1; // position of `operationCount` in the RateLimitData struct

        // calculate the actual storage slot
        bytes32 slot = bytes32(uint256(globalRateLimitSlotHash) + operationCountOffset);

        vm.store(
            address(paymaster),
            slot,
            bytes32(operationCount) // Make sure to properly cast the value to bytes32
        );
    }

    function _expectedRevertReason(string memory message) internal pure returns (bytes memory) {
        // prepare expected error message
        uint256 expectedOpIndex = 0; // Adjust as needed
        string memory expectedMessage = "AA33 reverted";
        bytes memory additionalMessage = abi.encodePacked(message);
        bytes memory expectedAdditionalData = abi.encodeWithSelector(
            bytes4(keccak256("Error(string)")), // Standard error selector
            additionalMessage
        );

        // encode the entire revert reason
        return abi.encodeWithSignature(
            "FailedOpWithRevert(uint256,string,bytes)", expectedOpIndex, expectedMessage, expectedAdditionalData
        );
    }

    /// @dev if batch is true, then we batch the increment ops
    // otherwise we do them one by one
    function _incrementCounterOps(uint256 amt, address app) internal returns (UserOperation[] memory userOps) {
        uint256 nonce = _kintoWallet.getNonce();
        userOps = new UserOperation[](amt);
        // we iterate from 1 because the first op is whitelisting the app
        for (uint256 i = 0; i < amt; i++) {
            userOps[i] = _createUserOperation(
                address(_kintoWallet),
                address(app),
                nonce,
                privateKeys,
                abi.encodeWithSignature("increment()"),
                address(_paymaster)
            );
            nonce++;
        }
    }

    /// @dev executes `amt` transactions with only one user op per tx
    function _incrementCounterTxs(uint256 amt, address app) internal {
        UserOperation[] memory userOps = new UserOperation[](1);
        for (uint256 i = 0; i < amt; i++) {
            userOps[0] = _incrementCounterOps(amt, app)[0];
            _entryPoint.handleOps(userOps, payable(_owner));
        }
    }

    /// @dev executes transactions until the gas limit is reached
    function _incrementCounterTxsUntilGasLimit(address app) internal returns (uint256 amt) {
        uint256[4] memory appLimits = _kintoAppRegistry.getContractLimits(address(counter));
        uint256 estimatedGasPerTx = 0;
        uint256 cumulativeGasUsed = 0;

        UserOperation[] memory userOps = new UserOperation[](1);
        while (cumulativeGasUsed < appLimits[3]) {
            if (cumulativeGasUsed + estimatedGasPerTx >= appLimits[3]) return amt;
            userOps[0] = _incrementCounterOps(1, app)[0]; // generate 1 user op

            uint256 beforeGas = gasleft();
            _entryPoint.handleOps(userOps, payable(_owner)); // execute the op

            if (amt == 0) estimatedGasPerTx = (beforeGas - gasleft());
            cumulativeGasUsed += estimatedGasPerTx;
            amt++;
        }
    }
}
