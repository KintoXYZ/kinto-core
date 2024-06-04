// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import "@kinto-core-test/SharedSetup.t.sol";
import {Create2Factory} from "@kinto-core/libraries/Create2Factory.sol";

import "@kinto-core/sample/Counter.sol";

contract Create2FactoryTest is SharedSetup {
    Create2Factory factory;

    function setUp() public virtual override {
        super.setUp();

        factory = new Create2Factory(_kintoID);
    }

    function testDeployCreate2_RevertWhen_CallerHasNoKYC() public {
        vm.prank(_user);
        (bool success, bytes memory returnData) =
            address(factory).call(abi.encode(bytes32(""), type(Counter).creationCode));

        assertEq(success, false, "Call succeed");
        assertEq(returnData.length, 36);
        assertEq(returnData, abi.encodeWithSignature("KYCRequired(address)", _user));
    }

    function testDeployCreate2(bytes32 salt) public {
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
