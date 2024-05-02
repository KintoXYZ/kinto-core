// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {CommonBase} from "forge-std/Base.sol";
import {console2} from "forge-std/console2.sol";

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

    function deploy(bytes32 salt, bytes memory creationCode) internal returns (address addr) {
        return deploy(0, salt, creationCode);
    }

    function deploy(uint256 amount, bytes32 salt, bytes memory creationCode) internal returns (address addr) {
        (bool success, bytes memory returnData) =
            CREATE2_FACTORY.call{value: amount}(abi.encodePacked(salt, creationCode));

        require(success, "Create2: Deployment failed");
        require(returnData.length == 20, "Create2: Returned data size is wrong");

        assembly {
            addr := mload(add(returnData, 20))
        }
    }
}
