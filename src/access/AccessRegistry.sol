// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin-5.0.1/contracts/utils/Address.sol";
import "@openzeppelin-5.0.1/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin-5.0.1/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin-5.0.1/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin-5.0.1/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin-5.0.1/contracts/interfaces/IERC20.sol";
import "@openzeppelin-5.0.1/contracts/utils/Create2.sol";
import "@openzeppelin-5.0.1/contracts/proxy/beacon/UpgradeableBeacon.sol";

import {BaseAccount} from "@aa-v7/core/BaseAccount.sol";
import {TokenCallbackHandler} from "@aa-v7/samples/callback/TokenCallbackHandler.sol";

import {ByteSignature} from "@kinto-core/libraries/ByteSignature.sol";
import {AccessPoint} from "@kinto-core/access/AccessPoint.sol";
import {Constants} from "@kinto-core/libraries/Const.sol";

import "../interfaces/IAccessRegistry.sol";

/**
 * @title Access Registry
 * @notice This contract serves as a registry for access points, associating each user
 * with a unique proxy and managing permissions for various workflows.
 * @dev Manages the lifecycle of access points and their associations with users, ensuring
 * each user has a unique, non-transferable access point.
 * Utilizes an UpgradeableBeacon for creating proxies, allowing future upgrades of
 * the access point implementations.
 */
contract AccessRegistry is Initializable, UUPSUpgradeable, OwnableUpgradeable, IAccessRegistry {
    /* ============ Constants ============ */

    /* ============ State Variables ============ */
    uint256 public override accessPointVersion;
    UpgradeableBeacon public immutable beacon;

    /* ============ Internal storage ============ */

    mapping(address => IAccessPoint) internal _accessPoints;
    mapping(address => bool) internal _workflows;

    /* ============ Modifiers ============ */

    /* ============ Constructor & Upgrades ============ */
    constructor(UpgradeableBeacon beacon_) {
        beacon = beacon_;

        _disableInitializers();
    }

    /// @dev initialize the proxy
    function initialize() external virtual initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        accessPointVersion = 1;
    }

    /// @inheritdoc IAccessRegistry
    function upgradeAll(IAccessPoint newImpl) external override onlyOwner {
        require(address(newImpl) != address(0) && address(newImpl) != beacon.implementation(), "invalid address");
        accessPointVersion++;
        emit AccessPointFactoryUpgraded(beacon.implementation(), address(newImpl));
        beacon.upgradeTo(address(newImpl));
    }

    /**
     * @dev Authorize the upgrade. Only by an owner.
     * @param newImplementation address of the new implementation
     */
    // This function is called by the proxy contract when the factory is upgraded
    function _authorizeUpgrade(address newImplementation) internal view override onlyOwner {
        (newImplementation);
    }

    /* ============ View Functions ============ */

    /// @inheritdoc IAccessRegistry
    function isWorkflowAllowed(address workflow) external view returns (bool) {
        return _workflows[workflow];
    }

    /// @inheritdoc IAccessRegistry
    function getAccessPoint(address user) external view returns (IAccessPoint accessPoint) {
        accessPoint = _accessPoints[user];
    }

    /// @inheritdoc IAccessRegistry
    function getAddress(address owner) public view override returns (address) {
        return Create2.computeAddress(
            bytes32(abi.encodePacked(owner)),
            keccak256(
                abi.encodePacked(
                    Constants.safeBeaconProxyCreationCode,
                    abi.encode(address(beacon), abi.encodeCall(IAccessPoint.initialize, (owner)))
                )
            )
        );
    }

    /**
     * @inheritdoc IAccessRegistry
     * @dev Salt is ignored on purpose. This method is added to provide / compliance with SimpleAccountFactory.
     * https://github.com/eth-infinitism/account-abstraction/blob/develop/contracts/samples/SimpleAccountFactory.sol
     */
    function getAddress(address owner, uint256) external view returns (address) {
        return getAddress(owner);
    }

    /* ============ State Change ============ */

    /// @inheritdoc IAccessRegistry
    function disallowWorkflow(address workflow) external onlyOwner {
        if (_workflows[workflow] == false) {
            revert WorkflowAlreadyDisallowed(workflow);
        }
        _workflows[workflow] = false;
        emit WorkflowStatusChanged(workflow, false);
    }

    /// @inheritdoc IAccessRegistry
    function allowWorkflow(address workflow) external onlyOwner {
        if (_workflows[workflow] == true) {
            revert WorkflowAlreadyAllowed(workflow);
        }
        _workflows[workflow] = true;
        emit WorkflowStatusChanged(workflow, true);
    }

    /// @inheritdoc IAccessRegistry
    function deployFor(address user) external override returns (IAccessPoint accessPoint) {
        return _deploy(user);
    }

    /**
     * @inheritdoc IAccessRegistry
     * @dev Salt is ignored on purpose. This method is added to provide / compliance with SimpleAccountFactory.
     * https://github.com/eth-infinitism/account-abstraction/blob/develop/contracts/samples/SimpleAccountFactory.sol
     */
    function createAccount(address user, uint256) external override returns (IAccessPoint accessPoint) {
        return _deploy(user);
    }

    /* ============ Internal ============ */

    /// @dev See `deploy`.
    function _deploy(address owner) internal returns (IAccessPoint accessPoint) {
        address addr = getAddress(owner);
        if (addr.code.length > 0) {
            return IAccessPoint(addr);
        }

        // Use the address of the owner as the CREATE2 salt.
        bytes32 salt = bytes32(abi.encodePacked(owner));

        // Deploy the accessPoint with CREATE2.
        accessPoint = IAccessPoint(
            Create2.deploy(
                0,
                salt,
                abi.encodePacked(
                    Constants.safeBeaconProxyCreationCode,
                    abi.encode(address(beacon), abi.encodeWithSignature("initialize(address)", owner))
                )
            )
        );

        // Associate the owner and the accessPoint.
        _accessPoints[owner] = accessPoint;

        // Log the creation of the accessPoint.
        emit DeployAccessPoint({operator: msg.sender, owner: owner, accessPoint: accessPoint});
    }
}
