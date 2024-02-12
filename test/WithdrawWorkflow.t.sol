// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@aa/core/EntryPoint.sol";

import "../src/access/AccessRegistry.sol";
import "../src/access/AccessPoint.sol";
import "../src/access/workflows/WithdrawWorkflow.sol";
import "../src/interfaces/IAccessPoint.sol";
import "../src/interfaces/IKintoEntryPoint.sol";
import "../src/paymasters/SignaturePaymaster.sol";

import "./helpers/UserOp.sol";
import "./helpers/ERC20Mock.sol";
import "./helpers/UUPSProxy.sol";

contract WithdrawWorkflowTest is UserOp {
    using ECDSA for bytes32;

    SignaturePaymaster paymaster;
    IKintoEntryPoint entryPoint;
    AccessRegistry internal accessRegistry;
    IAccessPoint internal accessPoint;
    WithdrawWorkflow internal withdrawWorkflow;
    ERC20Mock internal token;

    uint48 internal validUntil = 0xdeadbeef;
    uint48 internal validAfter = 1234;

    uint256 internal defaultAmount = 1e3 * 1e18;

    function setUp() public {
        vm.deal(_owner, 100 ether);
        token = new ERC20Mock("Token", "TNK", 18);

        entryPoint = IKintoEntryPoint(address(new EntryPoint{salt: 0}()));

        // use random address for access point implementation to avoid circular dependency
        UpgradeableBeacon beacon = new UpgradeableBeacon(address(this));
        IAccessRegistry accessRegistryImpl = new AccessRegistry(beacon);
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
            1,
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
            1,
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
            1,
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
