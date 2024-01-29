// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/utils/Create2.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

import "@aa/core/BaseAccount.sol";
import "@aa/samples/callback/TokenCallbackHandler.sol";

import "../libraries/ByteSignature.sol";
import "./AccessPoint.sol";
import "../proxy/SafeBeaconProxy.sol";

import "../interfaces/IAccessRegistry.sol";

contract AccessRegistry is Initializable, UUPSUpgradeable, OwnableUpgradeable, IAccessRegistry {
    /* ============ Constants ============ */

    /* ============ State Variables ============ */
    uint256 public override factoryVersion;
    UpgradeableBeacon public beacon;

    /* ============ Internal storage ============ */

    mapping(address => IAccessPoint) internal _accessPoints;
    mapping(address => bool) internal _workflows;

    /* ============ Modifiers ============ */

    /// @notice Checks that the caller has a accessPoint.
    modifier onlyCallerWithAccessPoint() {
        if (address(_accessPoints[msg.sender]) == address(0)) {
            revert UserDoesNotHaveAccessPoint(msg.sender);
        }
        _;
    }

    /// @notice Check that the user does not have a accessPoint.
    modifier onlyNonAccessPointOwner(address user) {
        IAccessPoint accessPoint = _accessPoints[user];
        if (address(accessPoint) != address(0)) {
            revert UserHasAccessPoint(user, accessPoint);
        }
        _;
    }

    /* ============ Constructor & Upgrades ============ */
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Upgrade calling `upgradeTo()`
     */
    function initialize(IAccessPoint impl) external virtual initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();
        beacon = new UpgradeableBeacon(address(impl));
        factoryVersion = 1;
    }

    /**
     * @dev Upgrade the wallet implementations using the beacon
     * @param newImpl The new implementation
     */
    function upgradeAll(IAccessPoint newImpl) external override onlyOwner {
        require(address(newImpl) != address(0) && address(newImpl) != beacon.implementation(), "invalid address");
        factoryVersion++;
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
                    type(SafeBeaconProxy).creationCode,
                    abi.encode(address(beacon), abi.encodeCall(IAccessPoint.initialize, (owner)))
                )
            )
        );
    }

    /// @dev TODO:Should be removed. Added because Kinto EntryPoint needs this function.
    function getWalletTimestamp(address) external pure returns (uint256) {
        return 1;
    }

    /* ============ State Change ============ */

    /// @inheritdoc IAccessRegistry
    function disallowWorkflow(address workflow) external onlyOwner {
        _workflows[workflow] = false;
        emit WorkflowStatusChanged(workflow, false);
    }

    /// @inheritdoc IAccessRegistry
    function allowWorkflow(address workflow) external onlyOwner {
        _workflows[workflow] = true;
        emit WorkflowStatusChanged(workflow, true);
    }

    /// @inheritdoc IAccessRegistry
    function deployFor(address user)
        external
        override
        onlyNonAccessPointOwner(user)
        returns (IAccessPoint accessPoint)
    {
        return _deploy(user);
    }

    /* ============ Internal ============ */

    /// @dev See `deploy`.
    function _deploy(address owner) internal returns (IAccessPoint accessPoint) {
        // Use the address of the owner as the CREATE2 salt.
        bytes32 salt = bytes32(abi.encodePacked(owner));

        // Deploy the accessPoint with CREATE2.
        accessPoint = IAccessPoint(
            payable(new SafeBeaconProxy{salt: salt}(address(beacon), abi.encodeCall(IAccessPoint.initialize, (owner))))
        );

        // Associate the owner and the accessPoint.
        _accessPoints[owner] = accessPoint;

        // Log the creation of the accessPoint.
        emit DeployAccessPoint({operator: msg.sender, owner: owner, accessPoint: accessPoint});
    }
}
