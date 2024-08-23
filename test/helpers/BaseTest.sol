// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {console2} from "forge-std/console2.sol";
import {AssertionHelper} from "./AssertionHelper.sol";

abstract contract BaseTest is AssertionHelper {
    // Reasonable block.timestamp `MAY_1_2023`
    uint32 internal constant START_TIMESTAMP = 1_682_899_200;

    // users
    uint256 internal _ownerPk = 111;
    address payable internal _owner = payable(vm.addr(_ownerPk));

    uint256 internal _secondownerPk = 2;
    address payable internal _secondowner = payable(vm.addr(_secondownerPk));

    uint256 internal _userPk = 3;
    address payable internal _user = payable(vm.addr(_userPk));

    uint256 internal _user2Pk = 4;
    address payable internal _user2 = payable(vm.addr(_user2Pk));

    uint256 internal _user3Pk = 33;
    address payable internal _user3 = payable(vm.addr(_user3Pk));

    uint256 internal _upgraderPk = 5;
    address payable internal _upgrader = payable(vm.addr(_upgraderPk));

    uint256 internal _kycProviderPk = 6;
    address payable internal _kycProvider = payable(vm.addr(_kycProviderPk));

    uint256 internal _recovererPk = 7;
    address payable internal _recoverer = payable(vm.addr(_recovererPk));

    uint256 internal _funderPk = 8;
    address payable internal _funder = payable(vm.addr(_funderPk));

    uint256 internal _verifierPk = 9;
    address payable internal _verifier = payable(vm.addr(_verifierPk));

    uint256 internal _noKycPk = 10;
    address payable internal _noKyc = payable(vm.addr(_noKycPk));

    uint256 internal adminPk;
    address internal admin;

    address[] internal users;

    uint256 internal alicePk;
    address internal alice;

    uint256 internal bobPk;
    address internal bob;

    uint256 internal ianPk;
    address internal ian;

    uint256 internal hannahPk;
    address internal hannah;

    uint256 internal georgePk;
    address internal george;

    uint256 internal frankPk;
    address internal frank;

    uint256 internal davidPk;
    address internal david;

    uint256 internal charliePk;
    address internal charlie;

    uint256 internal evePk;
    address internal eve;

    function setUp() public virtual {
        if (block.chainid == 31337) {
            // Set block.timestamp to something better than 0
            vm.warp(START_TIMESTAMP);
        }

        (admin, adminPk) = createUserWithKey("admin");
        (alice, alicePk) = createUserWithKey("alice");
        (bob, bobPk) = createUserWithKey("bob");
        (charlie, charliePk) = createUserWithKey("charlie");
        (david, davidPk) = createUserWithKey("david");
        (eve, evePk) = createUserWithKey("eve");
        (frank, frankPk) = createUserWithKey("frank");
        (george, georgePk) = createUserWithKey("george");
        (hannah, hannahPk) = createUserWithKey("hannah");
        (ian, ianPk) = createUserWithKey("ian");

        users = [alice, bob, charlie, david, eve, frank, george, hannah, ian];
    }

    function testUp() public virtual {}

    /// @dev Generates a user, labels its address, and funds it with test assets.
    function createUser(string memory name) internal returns (address payable) {
        (address addr,) = createUserWithKey(name);
        return payable(addr);
    }

    /// @dev Generates a user, labels its address, and funds it with test assets.
    function createUserWithKey(string memory name) internal returns (address addr, uint256 privateKey) {
        (addr, privateKey) = makeAddrAndKey(name);

        vm.label(addr, name);
        vm.deal(addr, 100e18);
    }
}
