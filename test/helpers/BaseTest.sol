// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

abstract contract BaseTest is Test {
    // private keys
    uint256 internal _ownerPk = 1;
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

    function setUp() public virtual {}

    function testUp() public virtual {}

    /// @dev Generates a user, labels its address, and funds it with test assets.
    function createUser(string memory name) internal returns (address payable) {
        address payable user = payable(makeAddr(name));
        vm.label(user, name);
        vm.deal(user, 100e18);

        return user;
    }
}
