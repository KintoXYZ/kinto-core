// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./IAccessPoint.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

/**
 * @title IAccessRegistry
 *  @notice Deploys new proxies via CREATE2 and keeps a registry of owners to proxies. Proxies can only be deployed
 *  once per owner, and they cannot be transferred. The registry also supports installing callbacks, which are used
 *  for extending the functionality of the access point.
 */
interface IAccessRegistry {
    /* ============ Errors ============ */

    /// @notice Thrown when a function requires the user to have a accessPoint.
    error UserDoesNotHaveAccessPoint(address user);

    /// @notice Thrown when a function requires the user to not have a accessPoint.
    error UserHasAccessPoint(address user, IAccessPoint accessPoint);

    /* ============ Events ============ */

    /// @notice Emitted when workflow is allowed or dissallowed.
    event WorkflowStatusChanged(address indexed workflow, bool indexed status);

    /// @notice Emitted when access point is upgraded.
    event AccessPointFactoryUpgraded(address indexed beacon, address indexed accessPoint);

    /// @notice Emitted when a new access point is deployed.
    event DeployAccessPoint(address indexed operator, address indexed owner, IAccessPoint accessPoint);

    /* ============ Structs ============ */

    /* ============ View Functions ============ */

    /// @notice
    function isWorkflowAllowed(address workflow) external view returns (bool);

    /// @notice Retrieves the accessPoint for the provided user.
    /// @param user The user address for the query.
    function getAccessPoint(address user) external view returns (IAccessPoint accessPoint);

    /**
     * @dev Calculates the counterfactual address of this account as it would be returned by deploy()
     * @param owner The owner address
     * @return The address of the account
     */
    function getAddress(address owner) external view returns (address);

    function beacon() external view returns (UpgradeableBeacon);

    function factoryVersion() external view returns (uint256);

    /* ============ State Change ============ */

    /// @notice
    function disallowWorkflow(address workflow) external;

    /// @notice
    function allowWorkflow(address workflow) external;

    function upgradeAll(IAccessPoint newImplementationWallet) external;

    /// @notice Deploys a new access point for the provided user.
    ///
    /// @dev Emits a {DeployAccessPoint} event.
    ///
    /// Requirements:
    /// - The user must not have a access point already.
    ///
    /// @param user The address that will own the access point.
    /// @return accessPoint The address of the newly deployed access point.
    function deployFor(address user) external returns (IAccessPoint accessPoint);
}
