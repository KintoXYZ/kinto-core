// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../src/sample/CounterInitializable.sol";
import {OwnableCounter as Counter} from "../src/sample/OwnableCounter.sol";

import "./helpers/UserOp.sol";
import "./helpers/UUPSProxy.sol";
import {AATestScaffolding} from "./helpers/AATestScaffolding.sol";

contract DeveloperDeployTest is UserOp, AATestScaffolding {
    uint256 _chainID = 1;

    UUPSProxy _proxyc;
    Counter _counter;
    CounterInitializable _counterInit;

    function setUp() public {
        vm.chainId(_chainID);
        vm.startPrank(address(1));
        _owner.transfer(1e18);
        vm.stopPrank();
        deployAAScaffolding(_owner, 1, _kycProvider, _recoverer);
        vm.startPrank(_owner);

        address created =
            _walletFactory.deployContract(_owner, 0, abi.encodePacked(type(Counter).creationCode), bytes32(0));
        _counter = Counter(created);

        created = _walletFactory.deployContract(
            _owner, 0, abi.encodePacked(type(CounterInitializable).creationCode), bytes32(0)
        );

        // deploy _proxy contract and point it to _implementation
        _proxyc = new UUPSProxy{salt: 0}(address(created), "");
        // wrap in ABI to support easier calls
        _counterInit = CounterInitializable(address(_proxyc));
        // Initialize proxy
        _counterInit.initialize(_user2);
        vm.stopPrank();
    }

    function testUp() public {
        assertEq(address(_owner), _counter.owner());
        assertEq(_user2, _counterInit.owner());
    }
}
