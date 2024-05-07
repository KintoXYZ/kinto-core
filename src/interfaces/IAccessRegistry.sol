// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {IAccessPoint} from "./IAccessPoint.sol";
import {UpgradeableBeacon} from "@openzeppelin-5.0.1/contracts/proxy/beacon/UpgradeableBeacon.sol";

/**
 * @title Access Registry Interface
 * @notice Manages and deploys new proxy contracts using CREATE2, maintaining a registry linking owners to proxies.
 * Each owner can only have one proxy, which is non-transferable.
 */
interface IAccessRegistry {
    /* ============ Errors ============ */

    /// @notice Thrown when a target workflow is already disallowed.
    error WorkflowAlreadyDisallowed(address workflow);

    /// @notice Thrown when a target workflow is already allowed.
    error WorkflowAlreadyAllowed(address workflow);

    /// @notice Thrown when a function requires the user to have a accessPoint.
    error UserDoesNotHaveAccessPoint(address user);

    /// @notice Thrown when a function requires the user to not have a accessPoint.
    error UserHasAccessPoint(address user, IAccessPoint accessPoint);

    /* ============ Events ============ */

    /// @notice Emitted when a workflow's allowance status is changed.
    event WorkflowStatusChanged(address indexed workflow, bool indexed status);

    /// @notice Emitted when the access point factory is upgraded.
    event AccessPointFactoryUpgraded(address indexed beacon, address indexed newAccessPoint);

    /// @notice Emitted when a new access point is deployed for a user.
    event DeployAccessPoint(address indexed operator, address indexed owner, IAccessPoint accessPoint);

    /* ============ View Functions ============ */

    /// @notice Checks if a workflow is currently allowed.
    /// @param workflow The address of the workflow to check.
    /// @return status True if the workflow is allowed, false otherwise.
    function isWorkflowAllowed(address workflow) external view returns (bool status);

    /// @notice Retrieves the access point associated with a user.
    /// @param user The user address for which to retrieve the access point.
    /// @return accessPoint The access point associated with the user.
    function getAccessPoint(address user) external view returns (IAccessPoint accessPoint);

    /**
     * @notice Calculates the address of a proxy that could be deployed via `deployFor`.
     * @param owner The owner address for which to calculate the proxy address.
     * @return The address of the proxy.
     */
    function getAddress(address owner) external view returns (address);

    /**
     * @notice Calculates the address of a proxy that could be deployed with a specified salt.
     * @param owner The owner address for which to calculate the proxy address.
     * @param salt The salt to use in the CREATE2 deployment process.
     * @return The address of the proxy.
     */
    function getAddress(address owner, uint256 salt) external view returns (address);

    /// @notice Retrieves the beacon contract used for proxy upgrades.
    /// @return The beacon contract used for upgrades.
    function beacon() external view returns (UpgradeableBeacon);

    /// @notice Retrieves the version number of the factory.
    /// @return The factory version as a uint256.
    function factoryVersion() external view returns (uint256);

    /* ============ State Change Functions ============ */

    /// @notice Disallows a specified workflow.
    /// @param workflow The address of the workflow to disallow.
    function disallowWorkflow(address workflow) external;

    /// @notice Allows a specified workflow.
    /// @param workflow The address of the workflow to allow.
    function allowWorkflow(address workflow) external;

    /// @notice Upgrades all deployed access points to a new implementation.
    /// @param newImplementation The new access point implementation to upgrade to.
    function upgradeAll(IAccessPoint newImplementation) external;

    /// @notice Deploys a new access point for the specified user.
    /// @param user The address that will own the new access point.
    /// @return accessPoint The address of the newly deployed access point.
    function deployFor(address user) external returns (IAccessPoint accessPoint);

    /// @notice Creates a new access point account for the specified owner using a salt for deterministic deployment.
    /// @param owner The address that will own the new access point.
    /// @param salt The salt to use in the CREATE2 deployment process.
    /// @return accessPoint The address of the newly created access point account.
    function createAccount(address owner, uint256 salt) external returns (IAccessPoint accessPoint);
}
