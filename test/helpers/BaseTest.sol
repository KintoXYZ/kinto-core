// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {console2} from "forge-std/console2.sol";
import {AssertionHelper} from "./AssertionHelper.sol";

abstract contract BaseTest is AssertionHelper {
    // Reasonable block.timestamp `MAY_1_2023`
    uint32 internal constant START_TIMESTAMP = 1_682_899_200;

    // private keys
    uint256 internal _ownerPk = 111;
    uint256 internal _secondownerPk = 2;
    uint256 internal _userPk = 3;
    uint256 internal _user2Pk = 4;
    uint256 internal _upgraderPk = 5;
    uint256 internal _kycProviderPk = 6;
    uint256 internal _recovererPk = 7;
    uint256 internal _funderPk = 8;
    uint256 internal _verifierPk = 9;
    uint256 internal _noKycPk = 10;

    // users
    address payable internal _owner = payable(vm.addr(_ownerPk));
    address payable internal _secondowner = payable(vm.addr(_secondownerPk));
    address payable internal _user = payable(vm.addr(_userPk));
    address payable internal _user2 = payable(vm.addr(_user2Pk));
    address payable internal _upgrader = payable(vm.addr(_upgraderPk));
    address payable internal _kycProvider = payable(vm.addr(_kycProviderPk));
    address payable internal _recoverer = payable(vm.addr(_recovererPk));
    address payable internal _funder = payable(vm.addr(_funderPk));
    address payable internal _verifier = payable(vm.addr(_verifierPk));
    address payable internal _noKyc = payable(vm.addr(_noKycPk));

    function setUp() public virtual {
        if (block.chainid == 31337) {
            // Set block.timestamp to something better than 0
            vm.warp(START_TIMESTAMP);
        }
    }

    function testUp() public virtual {}

    /// @dev Generates a user, labels its address, and funds it with test assets.
    function createUser(string memory name) internal returns (address payable) {
        address payable user = payable(makeAddr(name));
        vm.label(user, name);
        vm.deal(user, 100e18);

        return user;
    }
}
