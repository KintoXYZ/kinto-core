// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../../src/KintoID.sol";
import "../../src/interfaces/IKintoID.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "forge-std/console.sol";

abstract contract Create2Helper {
    using ECDSAUpgradeable for bytes32;
    using SignatureChecker for address;

    /* solhint-disable var-name-mixedcase */
    /* solhint-disable private-vars-leading-underscore */
    address CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    /// @notice Precompute a contract address deployed via CREATE2
    function computeAddress(uint256 salt, bytes memory creationCode) internal view returns (address) {
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
