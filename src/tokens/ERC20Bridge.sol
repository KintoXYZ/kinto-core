// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import "@openzeppelin-5.0.1/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin-5.0.1/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin-5.0.1/contracts/access/AccessControl.sol";

/**
 * @title ERC20Bridge
 * @notice Implements an ERC20 token with bridging capabilities for cross-chain asset transfers.
 * Extends OpenZeppelin's ERC20, ERC20Permit, and AccessControl.
 * @dev Introduces `mint` and `burn` functions secured with the `MINTER_ROLE` for bridging processes.
 * Inherits ERC20 functionality, permit mechanism for gasless transactions, and role-based access control.
 */
abstract contract ERC20Bridge is ERC20, ERC20Permit, AccessControl {
    /// @notice Role hash for addresses that can mint and burn tokens as part of bridging.
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    /**
     * @notice Creates a new token with bridging capabilities.
     * @param name The token's name.
     * @param symbol The token's symbol.
     * @param admin The initial admin, typically the deployer or a governance entity, with rights to manage roles.
     * @param minter The initial minter address, granted MINTER_ROLE for minting and burning tokens.
     * @dev Uses role-based access control for role assignments. Grants the deploying address the default admin
     * role for role management and assigns the MINTER_ROLE to a specified minter.
     */
    constructor(string memory name, string memory symbol, address admin, address minter) ERC20(name, symbol) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, minter);
    }

    /**
     * @notice Mints tokens to `to`, increasing the total supply.
     * @param to The recipient of the minted tokens.
     * @param amount The quantity of tokens to mint.
     * @dev Requires MINTER_ROLE. Can be used by authorized entities for new tokens in bridge operations.
     */
    function mint(address to, uint256 amount) public onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    /**
     * @notice Burns tokens from `from`, reducing the total supply.
     * @param from The address whose tokens will be burned.
     * @param amount The quantity of tokens to burn.
     * @dev Requires MINTER_ROLE. Can be used by authorized entities to remove tokens in bridge operations.
     */
    function burn(address from, uint256 amount) public onlyRole(MINTER_ROLE) {
        _burn(from, amount);
    }
}
