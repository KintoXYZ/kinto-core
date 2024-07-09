// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import "@kinto-core-test/SharedSetup.t.sol";
import {Create2Factory} from "@kinto-core/libraries/Create2Factory.sol";

import "@kinto-core/sample/Counter.sol";

contract Create2FactoryTest is SharedSetup {
    Create2Factory factory;

    function setUp() public virtual override {
        super.setUp();

        factory = new Create2Factory(_kintoID, _walletFactory);
    }

    function testUp() public view override {
        assertEq(address(factory.kintoID()), address(_kintoID));
    }

    function testDeployCreate2_RevertWhenCallerNotAWalletContract() public {
        vm.prank(address(_walletFactory));
        (bool success, bytes memory returnData) =
            address(factory).call(abi.encode(bytes32(""), type(Counter).creationCode));

        assertEq(success, false, "Call succeed");
        assertEq(returnData.length, 36);
        assertEq(returnData, abi.encodeWithSignature("KYCRequired(address)", address(_walletFactory)));
    }

    function testDeployCreate2_RevertWhenCallerHasNoKYC() public {
        vm.prank(_user);
        (bool success, bytes memory returnData) =
            address(factory).call(abi.encode(bytes32(""), type(Counter).creationCode));

        assertEq(success, false, "Call succeed");
        assertEq(returnData.length, 36);
        assertEq(returnData, abi.encodeWithSignature("KYCRequired(address)", _user));
    }

    function testDeployCreate2Wallet(bytes32 salt) public {
        vm.prank(address(_kintoWallet));
        (bool success, bytes memory returnData) =
            address(factory).call(abi.encodePacked(salt, type(Counter).creationCode));

        assertEq(success, true, "Call failed");
        assertEq(returnData.length, 20);

        Counter counter;
        assembly {
            counter := mload(add(returnData, 20))
        }

        counter.increment();
        assertEq(counter.count(), 1);
    }

    function testDeployCreate2EOA(bytes32 salt) public {
        vm.prank(_owner);
        (bool success, bytes memory returnData) =
            address(factory).call(abi.encodePacked(salt, type(Counter).creationCode));

        assertEq(success, true, "Call failed");
        assertEq(returnData.length, 20);

        Counter counter;
        assembly {
            counter := mload(add(returnData, 20))
        }

        counter.increment();
        assertEq(counter.count(), 1);
    }
}
