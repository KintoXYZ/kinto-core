// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {ERC20PermitUpgradeable} from
    "@openzeppelin-5.0.1/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin-5.0.1/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin-5.0.1/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {Initializable} from "@openzeppelin-5.0.1/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin-5.0.1/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title SuperToken
 * @notice Implements an ERC20 token with bridging capabilities for cross-chain asset transfers.
 * Extends OpenZeppelin's ERC20, ERC20Permit, and AccessControl.
 * @dev Introduces `mint` and `burn` functions secured with the `CONTROLLER_ROLE` for bridging processes.
 * Inherits ERC20 functionality, permit mechanism for gasless transactions, and role-based access control.
 */
contract SuperToken is
    Initializable,
    ERC20Upgradeable,
    ERC20PermitUpgradeable,
    AccessControlUpgradeable,
    UUPSUpgradeable
{
    uint8 private immutable _decimals;

    /// @notice for all controller access (mint, burn)
    bytes32 constant CONTROLLER_ROLE = keccak256("CONTROLLER_ROLE");

    /// @notice Role that can upgrade the implementation of the proxy.
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    /// @notice Thrown when input array lengths don't match in batch operations
    error ArrayLengthMismatch();
    /// @notice Thrown when empty arrays are provided to batch operations
    error EmptyArrays();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(uint8 decimals_) {
        _disableInitializers();
        _decimals = decimals_;
    }

    /**
     * @notice Creates a new token with bridging capabilities.
     * @param name The token's name.
     * @param symbol The token's symbol.
     * @param admin The initial admin, typically the deployer or a governance entity, with rights to manage roles.
     * @dev Uses role-based access control for role assignments. Grants the deploying address the default admin
     * role for role management and assigns the MINTER_ROLE to a specified minter.
     */
    function initialize(string memory name, string memory symbol, address admin) public initializer {
        __ERC20_init(name, symbol);
        __ERC20Permit_init(name);
        __AccessControl_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }

    /**
     * @dev Authorizes the contract upgrade.
     * Called by the proxy to ensure the caller has `UPGRADER_ROLE` before upgrading.
     *
     * @param newImplementation Address of the new contract implementation.
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}

    /**
     * @notice Mints tokens to `to`, increasing the total supply.
     * @param to The recipient of the minted tokens.
     * @param amount The quantity of tokens to mint.
     * @dev Requires MINTER_ROLE. Can be used by authorized entities for new tokens in bridge operations.
     */
    function mint(address to, uint256 amount) public onlyRole(CONTROLLER_ROLE) {
        _mint(to, amount);
    }

    /**
     * @notice Burns tokens from `from`, reducing the total supply.
     * @param from The address whose tokens will be burned.
     * @param amount The quantity of tokens to burn.
     * @dev Requires MINTER_ROLE. Can be used by authorized entities to remove tokens in bridge operations.
     */
    function burn(address from, uint256 amount) public onlyRole(CONTROLLER_ROLE) {
        _burn(from, amount);
    }

    /**
     * @notice Mints tokens to multiple addresses in a single transaction.
     * @param recipients Array of addresses to receive the minted tokens.
     * @param amounts Array of token amounts to mint to each recipient.
     * @dev Requires MINTER_ROLE. Reverts if array lengths don't match or if arrays are empty.
     * Can be used for batch bridging operations to optimize gas costs.
     */
    function batchMint(address[] calldata recipients, uint256[] calldata amounts) public onlyRole(CONTROLLER_ROLE) {
        if (recipients.length != amounts.length) revert ArrayLengthMismatch();
        if (recipients.length == 0) revert EmptyArrays();

        for (uint256 i = 0; i < recipients.length; i++) {
            _mint(recipients[i], amounts[i]);
        }
    }

    /**
     * @notice Burns tokens from multiple addresses in a single transaction.
     * @param from Array of addresses to burn tokens from.
     * @param amounts Array of token amounts to burn from each address.
     * @dev Requires MINTER_ROLE. Reverts if array lengths don't match or if arrays are empty.
     * Can be used for batch bridging operations to optimize gas costs.
     */
    function batchBurn(address[] calldata from, uint256[] calldata amounts) public onlyRole(CONTROLLER_ROLE) {
        if (from.length != amounts.length) revert ArrayLengthMismatch();
        if (from.length == 0) revert EmptyArrays();

        for (uint256 i = 0; i < from.length; i++) {
            _burn(from[i], amounts[i]);
        }
    }
}
