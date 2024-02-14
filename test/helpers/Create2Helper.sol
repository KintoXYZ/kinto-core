// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../../src/KintoID.sol";
import "../../src/interfaces/IKintoID.sol";

abstract contract Create2Helper {
    address CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    /// @notice Precompute a contract address deployed via CREATE2
    function computeAddress(bytes32 salt, bytes memory creationCode) internal view returns (address) {
        return address(
            uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), CREATE2_DEPLOYER, salt, keccak256(creationCode)))))
        );
    }

    function isContract(address _addr) internal view returns (bool) {
        uint32 size;
        assembly {
            size := extcodesize(_addr)
        }
        return (size > 0);
    }
}
