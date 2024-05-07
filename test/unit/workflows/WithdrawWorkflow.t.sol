// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {IERC20} from "@openzeppelin-5.0.1/contracts/token/ERC20/IERC20.sol";
import {ECDSA} from "@openzeppelin-5.0.1/contracts/utils/cryptography/ECDSA.sol";
import {UpgradeableBeacon} from "@openzeppelin-5.0.1/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {MessageHashUtils} from "@openzeppelin-5.0.1/contracts/utils/cryptography/MessageHashUtils.sol";
import {EntryPoint} from "@aa/core/EntryPoint.sol";
import {UserOperation} from "@aa/interfaces/UserOperation.sol";

import {AccessRegistry} from "@kinto-core/access/AccessRegistry.sol";
import {AccessPoint} from "@kinto-core/access/AccessPoint.sol";
import {WithdrawWorkflow} from "@kinto-core/access/workflows/WithdrawWorkflow.sol";
import {IAccessPoint} from "@kinto-core/interfaces/IAccessPoint.sol";
import {IAccessRegistry} from "@kinto-core/interfaces/IAccessRegistry.sol";
import {IKintoEntryPoint} from "@kinto-core/interfaces/IKintoEntryPoint.sol";
import {SignaturePaymaster} from "@kinto-core/paymasters/SignaturePaymaster.sol";

import {AccessRegistryHarness} from "@kinto-core-test/harness/AccessRegistryHarness.sol";

import {UserOp} from "@kinto-core-test/helpers/UserOp.sol";
import {BaseTest} from "@kinto-core-test/helpers/BaseTest.sol";
import {ERC20Mock} from "@kinto-core-test/helpers/ERC20Mock.sol";
import {UUPSProxy} from "@kinto-core-test/helpers/UUPSProxy.sol";

contract WithdrawWorkflowTest is BaseTest, UserOp {
    using MessageHashUtils for bytes32;

    SignaturePaymaster paymaster;
    IKintoEntryPoint entryPoint;
    AccessRegistry internal accessRegistry;
    IAccessPoint internal accessPoint;
    WithdrawWorkflow internal withdrawWorkflow;
    ERC20Mock internal token;

    uint48 internal validUntil = 2;
    uint48 internal validAfter = 0;

    uint256 internal defaultAmount = 1e3 * 1e18;

    function setUp() public override {
        vm.deal(_owner, 100 ether);
        token = new ERC20Mock("Token", "TNK", 18);

        entryPoint = IKintoEntryPoint(address(new EntryPoint{salt: 0}()));

        // use random address for access point implementation to avoid circular dependency
        UpgradeableBeacon beacon = new UpgradeableBeacon(address(this), address(this));
        IAccessRegistry accessRegistryImpl = new AccessRegistryHarness(beacon);
        UUPSProxy accessRegistryProxy = new UUPSProxy{salt: 0}(address(accessRegistryImpl), "");

        accessRegistry = AccessRegistry(address(accessRegistryProxy));
        beacon.transferOwnership(address(accessRegistry));
        IAccessPoint accessPointImpl = new AccessPoint(entryPoint, accessRegistry);

        accessRegistry.initialize();
        accessRegistry.upgradeAll(accessPointImpl);
        accessPoint = accessRegistry.deployFor(address(_user));

        withdrawWorkflow = new WithdrawWorkflow();

        entryPoint.setWalletFactory(address(accessRegistry));
        accessRegistry.allowWorkflow(address(withdrawWorkflow));

        deployPaymaster(_owner);
    }

    function testWithdrawERC20ViaPaymaster() public {
        token.mint(address(accessPoint), defaultAmount);

        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = createUserOperationWithPaymaster(
            block.chainid,
            address(accessPoint),
            address(withdrawWorkflow),
            accessPoint.getNonce(),
            _userPk,
            abi.encodeWithSelector(WithdrawWorkflow.withdrawERC20.selector, IERC20(token), defaultAmount)
        );

        entryPoint.handleOps(userOps, payable(_user));

        assertEq(token.balanceOf(_user), defaultAmount);
    }

    function testWithdrawERC20() public {
        token.mint(address(accessPoint), defaultAmount);

        bytes memory data =
            abi.encodeWithSelector(WithdrawWorkflow.withdrawERC20.selector, IERC20(token), defaultAmount);

        vm.prank(_user);
        accessPoint.execute(address(withdrawWorkflow), data);

        assertEq(token.balanceOf(_user), defaultAmount);
    }

    function testWithdrawNativeViaPaymaster() public {
        vm.deal(address(accessPoint), defaultAmount);

        abi.encodeWithSelector(WithdrawWorkflow.withdrawNative.selector, defaultAmount);

        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = createUserOperationWithPaymaster(
            block.chainid,
            address(accessPoint),
            address(withdrawWorkflow),
            accessPoint.getNonce(),
            _userPk,
            abi.encodeWithSelector(WithdrawWorkflow.withdrawNative.selector, defaultAmount)
        );

        entryPoint.handleOps(userOps, payable(address(accessPoint)));

        assertEq(_user.balance, defaultAmount);
    }

    function testWithdrawNative() public {
        vm.deal(address(accessPoint), defaultAmount);

        bytes memory data = abi.encodeWithSelector(WithdrawWorkflow.withdrawNative.selector, defaultAmount);

        vm.prank(_user);
        accessPoint.execute(address(withdrawWorkflow), data);

        assertEq(_user.balance, defaultAmount);
    }

    /// Utils

    function deployPaymaster(address _owner) public {
        vm.startPrank(_owner);

        // deploy the paymaster
        paymaster = new SignaturePaymaster{salt: 0}(entryPoint, _verifier);

        // deploy _proxy contract and point it to _implementation
        UUPSProxy proxyPaymaster = new UUPSProxy{salt: 0}(address(paymaster), "");

        // wrap in ABI to support easier calls
        paymaster = SignaturePaymaster(address(proxyPaymaster));

        // initialize proxy
        paymaster.initialize(_owner);

        paymaster.deposit{value: 10 ether}();

        vm.stopPrank();
    }

    function createUserOperationWithPaymaster(
        uint256 _chainID,
        address _from,
        address _target,
        uint256 _nonce,
        uint256 _privateKey,
        bytes memory _bytesOp
    ) internal view returns (UserOperation memory op) {
        op = createUserOperation(
            _chainID,
            _from,
            _target,
            _nonce,
            _privateKey,
            _bytesOp,
            abi.encodePacked(paymaster, abi.encode(validUntil, validAfter), new bytes(65))
        );

        bytes32 hash = paymaster.getHash(op, validUntil, validAfter);
        hash = hash.toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_verifierPk, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        return createUserOperation(
            block.chainid,
            address(accessPoint),
            address(withdrawWorkflow),
            accessPoint.getNonce(),
            _userPk,
            _bytesOp,
            abi.encodePacked(paymaster, abi.encode(validUntil, validAfter), signature)
        );
    }

    function createUserOperation(
        uint256 _chainID,
        address _from,
        address _target,
        uint256 _nonce,
        uint256 _privateKey,
        bytes memory _bytesOp,
        bytes memory _paymasterAndData
    ) internal view returns (UserOperation memory op) {
        op = UserOperation({
            sender: _from,
            nonce: _nonce,
            initCode: bytes(""),
            callData: abi.encodeCall(IAccessPoint.execute, (_target, _bytesOp)),
            callGasLimit: CALL_GAS_LIMIT, // generate from call simulation
            verificationGasLimit: 210_000, // verification gas. will add create2 cost (3200+200*length) if initCode exists
            preVerificationGas: 21_000, // should also cover calldata cost.
            maxFeePerGas: MAX_FEE_PER_GAS, // grab from current gas
            maxPriorityFeePerGas: MAX_PRIORITY_FEE_PER_GAS, // grab from current gas
            paymasterAndData: _paymasterAndData, // paymaster and data
            signature: bytes("")
        });
        uint256[] memory keys = new uint256[](1);
        keys[0] = _privateKey;
        op.signature = _signUserOp(op, AccessPoint(payable(_from)).entryPoint(), _chainID, keys);
        return op;
    }
}
