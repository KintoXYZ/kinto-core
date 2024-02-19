// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./IAccessRegistry.sol";

interface IAccessPoint {
    /* ============ Errors ============ */

    /// @notice Thrown when a target contract reverts without a specified reason.
    error ExecutionReverted();

    /// @notice Thrown when an unauthorized workflow is invoked.
    error WorkflowUnauthorized(address target);

    /// @notice Thrown when an unauthorized account tries to execute a delegate call.
    error ExecutionUnauthorized(address owner, address caller, address target);

    /// @notice Thrown when a fallback called.
    error FallbackIsNotAllowed(bytes data);

    /// @notice Thrown when a non-contract address is passed as the target.
    error TargetNotContract(address target);

    /* ============ Events ============ */

    /// @notice Emitted when a target contract is delegate called.
    event Execute(address indexed target, bytes data, bytes response);

    /* ============ View functions ============ */

    /// @notice The address of the owner account or contract, which controls the access point.
    function owner() external view returns (address);

    /// @notice The address of the registry that has deployed this access point.
    function registry() external view returns (IAccessRegistry);

    /// @notice
    function getNonce() external view returns (uint256);

    /* ============ State Change ============ */

    /// @notice
    function initialize(address owner_) external;

    /// @notice Delegate calls to the provided target contract by forwarding the data. It returns the data it
    /// gets back, and bubbles up any potential revert.
    ///
    /// @dev Emits an {Execute} event.
    ///
    /// Requirements:
    /// - The caller must be either the owner or an envoy with permission.
    /// - `target` must be a contract.
    ///
    /// @param target The address of the target contract.
    /// @param data Function selector plus ABI encoded data.
    /// @return response The response received from the target contract, if any.
    function execute(address target, bytes calldata data) external payable returns (bytes memory response);
}
