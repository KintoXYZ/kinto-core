// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "@kinto-core/apps/KintoAppRegistry.sol";
import "@kinto-core/interfaces/IKintoAppRegistry.sol";

import "@kinto-core-test/SharedSetup.t.sol";

contract ContractCallTest is SharedSetup {
    address internal constant CREATE2 = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
    address internal appContract0 = makeAddr("appContract0");
    address internal sponsorContract0 = makeAddr("sponsorContract0");
    address internal sponsorContract1 = makeAddr("sponsorContract1");
    bytes4 internal emptySelector = bytes4(0);
    bytes4 internal selector = hex"deadcafe";
    bytes internal selectorCalldata = hex"deadcafe";

    function setUp() public virtual override {
        super.setUp();

        mockContractBytecode(appContract0);
        mockContractBytecode(sponsorContract0);
        mockContractBytecode(sponsorContract1);
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

    function testIsContractCallAllowedFromEOA_WhenDevEOA() public {
        address[] memory appContracts = new address[](2);
        appContracts[0] = address(11);
        mockContractBytecode(appContracts[0]);
        appContracts[1] = address(22);
        mockContractBytecode(appContracts[1]);

        address[] memory devEOAs = new address[](3);
        devEOAs[0] = _owner;
        devEOAs[1] = _user;
        devEOAs[2] = _user2;

        uint256[] memory appLimits = new uint256[](4);
        appLimits[0] = _kintoAppRegistry.RATE_LIMIT_PERIOD();
        appLimits[1] = _kintoAppRegistry.RATE_LIMIT_THRESHOLD();
        appLimits[2] = _kintoAppRegistry.GAS_LIMIT_PERIOD();
        appLimits[3] = _kintoAppRegistry.GAS_LIMIT_THRESHOLD();

        resetSigners(devEOAs, 1);

        vm.prank(address(_kintoWallet));
        _kintoAppRegistry.registerApp(
            "test", address(99), appContracts, [appLimits[0], appLimits[1], appLimits[2], appLimits[3]], devEOAs
        );

        assertEq(_kintoAppRegistry.isContractCallAllowedFromEOA(_owner, address(11), selectorCalldata, 0), true);
        assertEq(_kintoAppRegistry.isContractCallAllowedFromEOA(_user, address(11), selectorCalldata, 0), true);
        assertEq(_kintoAppRegistry.isContractCallAllowedFromEOA(_user2, address(22), selectorCalldata, 0), true);
    }

    /* ============ Helpers ============ */

    // Helper function to mock contract bytecode
    function mockContractBytecode(address _contract) internal {
        vm.etch(_contract, hex"00"); // Minimal bytecode
    }
}
