// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {IERC20} from "@openzeppelin-5.0.1/contracts/token/ERC20/IERC20.sol";
import {ECDSA} from "@openzeppelin-5.0.1/contracts/utils/cryptography/ECDSA.sol";
import {UpgradeableBeacon} from "@openzeppelin-5.0.1/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {MessageHashUtils} from "@openzeppelin-5.0.1/contracts/utils/cryptography/MessageHashUtils.sol";
import {EntryPoint} from "@aa/core/EntryPoint.sol";
import {UserOperation} from "@aa/interfaces/UserOperation.sol";

import {AccessRegistry} from "../src/access/AccessRegistry.sol";
import {AccessPoint} from "../src/access/AccessPoint.sol";
import {SwapWorkflow} from "../src/access/workflows/SwapWorkflow.sol";
import {IAccessPoint} from "../src/interfaces/IAccessPoint.sol";
import {IAccessRegistry} from "../src/interfaces/IAccessRegistry.sol";
import {IKintoEntryPoint} from "../src/interfaces/IKintoEntryPoint.sol";
import {SignaturePaymaster} from "../src/paymasters/SignaturePaymaster.sol";

import {AccessRegistryHarness} from "./harness/AccessRegistryHarness.sol";

import {UserOp} from "./helpers/UserOp.sol";
import {UUPSProxy} from "./helpers/UUPSProxy.sol";
import {SharedSetup} from "./SharedSetup.t.sol";

contract SwapWorkflowTest is UserOp, SharedSetup {
    using MessageHashUtils for bytes32;
    using stdJson for string;

    SignaturePaymaster paymaster;
    IKintoEntryPoint entryPoint;
    AccessRegistry internal accessRegistry;
    IAccessPoint internal accessPoint;
    SwapWorkflow internal swapWorkflow;

    uint48 internal validUntil = 2;
    uint48 internal validAfter = 0;

    uint256 internal defaultAmount = 1e3 * 1e6;

    address internal constant EXCHANGE_PROXY = 0xDef1C0ded9bec7F1a1670819833240f027b25EfF;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    function setUp() public override {
        super.setUp();

        if (!fork) vm.skip(true);

        string memory rpc = vm.envString("ETHEREUM_RPC_URL");
        require(bytes(rpc).length > 0, "ETHEREUM_RPC_URL is not set");

        vm.chainId(1);
        mainnetFork = vm.createFork(rpc);
        vm.selectFork(mainnetFork);
        assertEq(vm.activeFork(), mainnetFork);

        vm.deal(_owner, 100 ether);

        deploy();

        vm.label(EXCHANGE_PROXY, "EXCHANGE_PROXY");
    }

    function deploy() internal {
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
        vm.label(address(accessPoint), "accessPoint");

        swapWorkflow = new SwapWorkflow(EXCHANGE_PROXY);

        entryPoint.setWalletFactory(address(accessRegistry));
        accessRegistry.allowWorkflow(address(swapWorkflow));

        deployPaymaster(_owner);
    }

    function testSwapERC20() public {
        vm.rollFork(19725885); // block number in which the 0x API data was fetched
        deploy();

        string memory quote = vm.readFile("./test/data/swap-quote.json");
        bytes memory swapCallData = quote.readBytes(".data");
        bytes memory data = abi.encodeWithSelector(
            SwapWorkflow.fillQuote.selector, USDC, defaultAmount, DAI, defaultAmount * 99 / 100, swapCallData
        );

        deal(USDC, address(accessPoint), defaultAmount);
        vm.prank(_user);
        accessPoint.execute(address(swapWorkflow), data);

        // check that swap is executed
        assertEq(IERC20(USDC).balanceOf(address(accessPoint)), 0, "USDC balance is wrong");
        assertEq(IERC20(DAI).balanceOf(address(accessPoint)), 999842220668049737510, "DAI balance is wrong");
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
            address(swapWorkflow),
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
