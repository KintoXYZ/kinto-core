// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

contract Constants {
    uint256 internal constant LEDGER = 0;
    uint256 internal constant TREZOR = 1;
    address WUSDM = 0x57F5E098CaD7A3D1Eed53991D4d66C45C9AF7812; // wUSDM
    uint64 internal constant NIO_GOVERNOR_ROLE = uint64(uint256(keccak256("NIO_GOVERNOR_ROLE")));
    uint256 internal constant NIO_EXECUTION_DELAY = 3 days;
}
