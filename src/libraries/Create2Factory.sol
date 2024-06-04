// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {IKintoID} from "@kinto-core/interfaces/IKintoID.sol";

contract Create2Factory {
    /// @notice Error indicating that KYC is required for the sender.
    /// @param sender The address of the sender.
    error KYCRequired(address sender);

    /// @notice Error indicating that the transaction is rejected.
    /// @param sender The address of the sender.
    /// @param amount The amount sent with the transaction.
    error Reject(address sender, uint256 amount);

    IKintoID public kintoID;
    /// @notice The KintoID contract instance.

    /// @notice Constructor to initialize the KintoID contract.
    /// @param _kintoID The address of the KintoID contract.
    constructor(IKintoID _kintoID) {
        kintoID = _kintoID;
    }

    /// @notice Fallback function to handle contract creation using CREATE2.
    /// @return The address of the newly created contract.
    /// @dev Callldata contains salt (32 bytes) + creationCode.
    /// They are encoded with encodePacked.
    fallback(bytes calldata) external payable returns (bytes memory) {
        if (!kintoID.isKYC(msg.sender)) revert KYCRequired(msg.sender);

        assembly {
            // Load creationCode to position 0 in memory.
            // First 32 bytes of calldata contain salt.
            calldatacopy(0, 32, sub(calldatasize(), 32))
            // Create a contract using create2.
            // Calldata contains salt at position 0.
            let result := create2(callvalue(), 0, sub(calldatasize(), 32), calldataload(0))
            // If result is zero, then deployment failed.
            if iszero(result) { revert(0, 0) }
            // Store the address at memory position 0.
            mstore(0, result)
            // Return the 20 bytes of the address.
            return(12, 20)
        }
    }

    /// @notice Receive function to reject any incoming Ether transfers.
    receive() external payable {
        revert Reject(msg.sender, msg.value);
    }
}
