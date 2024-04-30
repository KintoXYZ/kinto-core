// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {CommonBase} from "forge-std/Base.sol";

interface Create2Factory {
    function deploy(uint256 amount, bytes32 salt, bytes memory creationCode) external payable returns (address addr);
}

abstract contract Create2Helper is CommonBase {
    /// @notice Precompute a contract address deployed via CREATE2
    function computeAddress(bytes memory creationCode) internal pure returns (address) {
        return computeAddress(0, creationCode);
    }

    /// @notice Precompute a contract address deployed via CREATE2
    function computeAddress(bytes32 salt, bytes memory creationCode) internal pure returns (address) {
        return address(
            uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), CREATE2_FACTORY, salt, keccak256(creationCode)))))
        );
    }

    function isContract(address _addr) internal view returns (bool) {
        uint32 size;
        assembly {
            size := extcodesize(_addr)
        }
        return (size > 0);
    }

    function deploy(bytes memory creationCode) internal returns (address addr) {
        return deploy(0, 0, creationCode);
    }

    function deploy(uint256 amount, bytes32 salt, bytes memory creationCode) internal returns (address addr) {
        return Create2Factory(CREATE2_FACTORY).deploy(amount, salt, creationCode);
    }
}
