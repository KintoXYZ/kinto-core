// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../src/sample/OwnableCounter.sol";
import "../src/sample/InitializableCounter.sol";
import "./SharedSetup.t.sol";
import "./helpers/UUPSProxy.sol";

contract DeveloperDeployTest is SharedSetup {
    OwnableCounter _ownableCounter;
    InitializableCounter _initializableCounter;

    function setUp() public override {
        super.setUp();

        // deploy ownable counter
        vm.prank(_owner);
        _ownableCounter = OwnableCounter(
            _walletFactory.deployContract(_owner, 0, abi.encodePacked(type(OwnableCounter).creationCode), bytes32(0))
        );

        // deploy initialisable counter
        vm.prank(_owner);
        address _implementation = _walletFactory.deployContract(
            _owner, 0, abi.encodePacked(type(InitializableCounter).creationCode), bytes32(0)
        );

        // deploy proxy contract for initialisable counter and point it to _implementation
        UUPSProxy _proxy = new UUPSProxy{salt: 0}(address(_implementation), "");

        // initialize proxy
        _initializableCounter = InitializableCounter(address(_proxy));
        vm.prank(_owner);
        _initializableCounter.initialize(_user2);
    }

    function testUp() public override {
        assertEq(address(_owner), _ownableCounter.owner());
        assertEq(_user2, _initializableCounter.owner());
    }
}
