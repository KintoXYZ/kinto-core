// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../../src/KintoID.sol";
import "../../src/interfaces/IKintoID.sol";

interface Create2Factory {
    function deploy(uint256 amount, bytes32 salt, bytes memory bytecode) external payable returns (address addr);
}

abstract contract Create2Helper {
    // Create2 contract deployer address on every chain
    address public constant CREATE2_FACTORY = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    /// @notice Precompute a contract address deployed via CREATE2
    function computeAddress(bytes32 salt, bytes memory creationCode) internal view returns (address) {
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

    function deploy(uint256 amount, bytes32 salt, bytes memory bytecode) internal returns (address addr) {
        return Create2Factory(CREATE2_FACTORY).deploy(amount, salt, bytecode);
    }
}
