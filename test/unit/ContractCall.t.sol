// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "@kinto-core/apps/KintoAppRegistry.sol";
import "@kinto-core/interfaces/IKintoAppRegistry.sol";

import "@kinto-core-test/SharedSetup.t.sol";

contract ContractCallTest is SharedSetup {
    address internal constant CREATE2 = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
    bytes4 internal emptySelector = bytes4(0);
    bytes4 internal selector = hex"deadcafe";
    bytes internal selectorCalldata = hex"deadcafe";
    address public constant ENTRYPOINT_V6 = 0x2843C269D2a64eCfA63548E8B3Fc0FD23B7F70cb;
    address public constant ENTRYPOINT_V7 = 0x0000000071727De22E5E9d8BAf0edAc6f37da032;
    address public constant ARB_RETRAYABLE_TX = 0x000000000000000000000000000000000000006E;

    function setUp() public virtual override {
        super.setUp();
    }

    /* ============ isContractCallAllowedFromEOA ============ */

    function testIsContractCallAllowedFromEOA_WhenSystemContract() public {
        // Update system contracts array
        address[] memory newSystemContracts = new address[](2);
        newSystemContracts[0] = address(1);
        newSystemContracts[1] = address(2);

        vm.prank(_owner);
        _kintoAppRegistry.updateSystemContracts(newSystemContracts);

        assertEq(_kintoAppRegistry.isContractCallAllowedFromEOA(_user, address(1), selectorCalldata, 0), true);
        assertEq(_kintoAppRegistry.isContractCallAllowedFromEOA(_user, address(2), selectorCalldata, 0), true);
    }

    function testIsContractCallAllowedFromEOA_WhenRandomEOACreate2() public view {
        assertEq(_kintoAppRegistry.isContractCallAllowedFromEOA(_user2, address(CREATE2), selectorCalldata, 0), false);
    }

    function testIsContractCallAllowedFromEOA_WhenRandomEOACreate() public view {
        assertEq(_kintoAppRegistry.isContractCallAllowedFromEOA(_user2, address(0), selectorCalldata, 0), false);
    }

    function testIsContractCallAllowedFromEOA_WhenRandomEOA() public view {
        assertEq(_kintoAppRegistry.isContractCallAllowedFromEOA(_user2, address(0xdead), selectorCalldata, 0), false);
    }

    function testIsContractCallAllowedFromEOA_WhenCreate2() public {
        vm.prank(address(_kintoWallet));
        _kintoAppRegistry.setDeployerEOA(address(_kintoWallet), address(0xde));

        assertEq(
            _kintoAppRegistry.isContractCallAllowedFromEOA(address(0xde), address(CREATE2), selectorCalldata, 0), true
        );
    }

    function testIsContractCallAllowedFromEOA_WhenCreate() public {
        vm.prank(address(_kintoWallet));
        _kintoAppRegistry.setDeployerEOA(address(_kintoWallet), address(0xde));

        assertEq(_kintoAppRegistry.isContractCallAllowedFromEOA(address(0xde), address(0), selectorCalldata, 0), true);
    }

    function testIsContractCallAllowedFromEOA_WhenEntryPointWithdraw() public view {
        bytes memory withdrawStakeCallData = abi.encodeWithSelector(bytes4(keccak256("withdrawStake(address)")), _user);
        bytes memory withdrawToCallData =
            abi.encodeWithSelector(bytes4(keccak256("withdrawTo(address,uint256)")), _user, 100);

        // Test withdrawStake
        assertEq(_kintoAppRegistry.isContractCallAllowedFromEOA(_user, ENTRYPOINT_V6, withdrawStakeCallData, 0), true);
        assertEq(_kintoAppRegistry.isContractCallAllowedFromEOA(_user2, ENTRYPOINT_V6, withdrawStakeCallData, 0), false);

        // Test withdrawTo
        assertEq(_kintoAppRegistry.isContractCallAllowedFromEOA(_user, ENTRYPOINT_V7, withdrawToCallData, 0), true);
        assertEq(_kintoAppRegistry.isContractCallAllowedFromEOA(_user2, ENTRYPOINT_V7, withdrawToCallData, 0), false);
    }

    function testIsContractCallAllowedFromEOA_WhenHandleOps() public view {
        address payable beneficiary = payable(address(0x456));
        bytes memory handleOpsCallData = abi.encodeWithSelector(bytes4(0x1fad948c), new bytes(0), beneficiary);
        bytes memory handleOpsV7CallData = abi.encodeWithSelector(bytes4(0x765e827f), new bytes(0), beneficiary);

        // Test handleOps
        assertEq(_kintoAppRegistry.isContractCallAllowedFromEOA(beneficiary, ENTRYPOINT_V6, handleOpsCallData, 0), true);
        assertEq(_kintoAppRegistry.isContractCallAllowedFromEOA(_user, ENTRYPOINT_V6, handleOpsCallData, 0), false);

        // Test handleOps V7
        assertEq(
            _kintoAppRegistry.isContractCallAllowedFromEOA(beneficiary, ENTRYPOINT_V7, handleOpsV7CallData, 0), true
        );
        assertEq(_kintoAppRegistry.isContractCallAllowedFromEOA(_user, ENTRYPOINT_V7, handleOpsV7CallData, 0), false);

        bytes memory handleAggregatedOpsCallData = abi.encodeWithSelector(bytes4(0x4b1d7cf5), new bytes(0), beneficiary);
        bytes memory handleAggregatedOpsV7CallData =
            abi.encodeWithSelector(bytes4(0xdbed18e0), new bytes(0), beneficiary);

        // Test handleAggregatedOps
        assertEq(
            _kintoAppRegistry.isContractCallAllowedFromEOA(beneficiary, ENTRYPOINT_V6, handleAggregatedOpsCallData, 0),
            true
        );
        assertEq(
            _kintoAppRegistry.isContractCallAllowedFromEOA(_user, ENTRYPOINT_V6, handleAggregatedOpsCallData, 0), false
        );

        // Test handleAggregatedOps V7
        assertEq(
            _kintoAppRegistry.isContractCallAllowedFromEOA(beneficiary, ENTRYPOINT_V7, handleAggregatedOpsV7CallData, 0),
            true
        );
        assertEq(
            _kintoAppRegistry.isContractCallAllowedFromEOA(_user, ENTRYPOINT_V7, handleAggregatedOpsV7CallData, 0),
            false
        );
    }

    function testIsContractCallAllowedFromEOA_WhenForbiddenEntryPointFunctions() public view {
        bytes memory depositCallData = abi.encodeWithSelector(bytes4(0xb760faf9), address(0x789));
        bytes memory emptyCallData = new bytes(0);

        assertEq(_kintoAppRegistry.isContractCallAllowedFromEOA(_user, ENTRYPOINT_V6, depositCallData, 0), false);
        assertEq(_kintoAppRegistry.isContractCallAllowedFromEOA(_user, ENTRYPOINT_V6, emptyCallData, 0), false);

        assertEq(_kintoAppRegistry.isContractCallAllowedFromEOA(_user, ENTRYPOINT_V7, depositCallData, 0), false);
        assertEq(_kintoAppRegistry.isContractCallAllowedFromEOA(_user, ENTRYPOINT_V7, emptyCallData, 0), false);
    }

    function testIsContractCallAllowedFromEOA_WhenSystemContracts() public {
        address systemContract = address(0xabc);
        address[] memory newSystemContracts = new address[](1);
        newSystemContracts[0] = systemContract;

        vm.prank(_owner);
        _kintoAppRegistry.updateSystemContracts(newSystemContracts);

        assertEq(_kintoAppRegistry.isContractCallAllowedFromEOA(_user, systemContract, new bytes(0), 0), true);
    }

    function testIsContractCallAllowedFromEOA_WhenDeployerEOA() public {
        address deployer = address(0xdef);

        vm.prank(address(_kintoWallet));
        _kintoAppRegistry.setDeployerEOA(address(_kintoWallet), deployer);

        assertEq(_kintoAppRegistry.isContractCallAllowedFromEOA(deployer, address(0), new bytes(0), 0), true);
        assertEq(_kintoAppRegistry.isContractCallAllowedFromEOA(deployer, CREATE2, new bytes(0), 0), true);
        assertEq(_kintoAppRegistry.isContractCallAllowedFromEOA(_user, address(0), new bytes(0), 0), false);
    }

    function testIsContractCallAllowedFromEOA_WhenDevEOA() public {
        address app = address(0x123);
        address childContract = address(0x456);
        address devEOA1 = address(0x789);
        address devEOA2 = address(0xabc);

        address[] memory appContracts = new address[](1);
        appContracts[0] = childContract;
        mockContractBytecode(childContract);

        address[] memory devEOAs = new address[](2);
        devEOAs[0] = devEOA1;
        devEOAs[1] = devEOA2;

        vm.prank(address(_kintoWallet));
        _kintoAppRegistry.registerApp(
            "TestApp", app, appContracts, [uint256(0), uint256(0), uint256(0), uint256(0)], devEOAs
        );

        assertTrue(_kintoAppRegistry.isContractCallAllowedFromEOA(devEOA1, app, new bytes(0), 0));
        assertTrue(_kintoAppRegistry.isContractCallAllowedFromEOA(devEOA1, childContract, new bytes(0), 0));
        assertTrue(_kintoAppRegistry.isContractCallAllowedFromEOA(devEOA2, devEOA1, new bytes(0), 0));
        assertFalse(_kintoAppRegistry.isContractCallAllowedFromEOA(_user, app, new bytes(0), 0));
    }

    function testIsContractCallAllowedFromEOA_WhenInvalidCases() public view {
        assertEq(_kintoAppRegistry.isContractCallAllowedFromEOA(_user, address(0), new bytes(0), 0), false);
        assertEq(_kintoAppRegistry.isContractCallAllowedFromEOA(_user, address(0x123), new bytes(0), 0), false);
    }

    function testIsContractCallAllowedFromEOA_WhenHardcodedSystemContracts() public view {
        assertTrue(_kintoAppRegistry.isContractCallAllowedFromEOA(_user, ENTRYPOINT_V6, selectorCalldata, 0));
        assertTrue(_kintoAppRegistry.isContractCallAllowedFromEOA(_user, ENTRYPOINT_V7, selectorCalldata, 0));
        assertTrue(_kintoAppRegistry.isContractCallAllowedFromEOA(_user, ARB_RETRAYABLE_TX, new bytes(0), 0));
        assertTrue(_kintoAppRegistry.isContractCallAllowedFromEOA(_user, address(_paymaster), new bytes(0), 0));
        assertTrue(_kintoAppRegistry.isContractCallAllowedFromEOA(_user, address(_kintoAppRegistry), new bytes(0), 0));
    }

    /* ============ Helpers ============ */

    // Helper function to mock contract bytecode
    function mockContractBytecode(address _contract) internal {
        vm.etch(_contract, hex"00"); // Minimal bytecode
    }
}
