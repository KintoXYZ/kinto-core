// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {console2} from "forge-std/console2.sol";
import {AssertionHelper} from "./AssertionHelper.sol";

abstract contract BaseTest is AssertionHelper {
    // Reasonable block.timestamp `MAY_1_2023`
    uint32 internal constant START_TIMESTAMP = 1_682_899_200;

    // signers
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

    address[] internal signers;
    uint256[] internal signersPk;

    uint256 internal admin0Pk;
    address internal admin0;

    uint256 internal alice0Pk;
    address internal alice0;

    uint256 internal bob0Pk;
    address internal bob0;

    uint256 internal ian0Pk;
    address internal ian0;

    uint256 internal hannah0Pk;
    address internal hannah0;

    uint256 internal george0Pk;
    address internal george0;

    uint256 internal frank0Pk;
    address internal frank0;

    uint256 internal david0Pk;
    address internal david0;

    uint256 internal charlie0Pk;
    address internal charlie0;

    uint256 internal eve0Pk;
    address internal eve0;

    function setUp() public virtual {
        if (block.chainid == 31337) {
            // Set block.timestamp to something better than 0
            vm.warp(START_TIMESTAMP);
        }

        (admin0, admin0Pk) = createUserWithKey("admin0");
        (alice0, alice0Pk) = createUserWithKey("alice0");
        (bob0, bob0Pk) = createUserWithKey("bob0");
        (charlie0, charlie0Pk) = createUserWithKey("charlie0");
        (david0, david0Pk) = createUserWithKey("david0");
        (eve0, eve0Pk) = createUserWithKey("eve0");
        (frank0, frank0Pk) = createUserWithKey("frank0");
        (george0, george0Pk) = createUserWithKey("george0");
        (hannah0, hannah0Pk) = createUserWithKey("hannah0");
        (ian0, ian0Pk) = createUserWithKey("ian0");

        signers = [admin0, alice0, bob0, charlie0, david0, eve0, frank0, george0, hannah0, ian0];
        signersPk = [admin0Pk, alice0Pk, bob0Pk, charlie0Pk, david0Pk, eve0Pk, frank0Pk, george0Pk, hannah0Pk, ian0Pk];
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
