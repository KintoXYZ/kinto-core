// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/// @custom:security-contact security@mamorilabs.com
contract EngenBadges is
    Initializable,
    ERC1155Upgradeable,
    AccessControlUpgradeable,
    UUPSUpgradeable,
    OwnableUpgradeable
{
    /* ============ Constants & Immutables ============ */

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    error NoTokenIDsProvided();
    error MismatchedInputLengths();
    error MintToManyAddresses();
    error BurnTooManyAddresses();

    string public constant name = "Engen Badges";
    string public constant symbol = "ENGB";

    /* ============ Constructor & Initializers ============ */

    /**
     * @dev Initializes the contract with a specific URI for metadata and sets up roles.
     * @param uri The base URI for the ERC1155 token metadata.
     */
    function initialize(string memory uri) external initializer {
        __ERC1155_init(uri);
        __AccessControl_init();
        __UUPSUpgradeable_init();

        // Set up roles for the provided admin address
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
        _grantRole(UPGRADER_ROLE, msg.sender);
    }

    /* ============ View functions ============ */

    /**
     * @dev Return all badge balances for a given wallet up to a specified badge ID.
     * @param wallet The address of the wallet to check.
     * @param upToId The highest badge ID to check.
     */
    function getAllBadges(address wallet, uint256 upToId) public view returns (uint256[] memory) {
        uint256[] memory balances = new uint256[](upToId + 1);
        for (uint256 i = 0; i <= upToId; i++) {
            balances[i] = balanceOf(wallet, i);
        }
        return balances;
    }

    /* ======= Privileged Functions ============ */

    /**
     * @dev Mints badges to a specified address with each ID only being minted once.
     * @param to The address to mint the badges to.
     * @param ids An array of token IDs to mint.
     */
    function mintBadges(address to, uint256[] memory ids) public onlyRole(MINTER_ROLE) {
        if (ids.length == 0) revert NoTokenIDsProvided();
        uint256[] memory amounts = new uint256[](ids.length);
        for (uint256 i = 0; i < ids.length; i++) {
            amounts[i] = 1; // Set the mint amount for each badge to exactly one.
        }
        _mintBatch(to, ids, amounts, "");
    }

    /**
     * @dev Batch minting function that reuses mintBadges to mint multiple types of tokens to multiple addresses,
     * each ID being minted exactly once per specified recipient. Limits the batch to a maximum of 100 addresses.
     * @param recipients List of recipient addresses.
     * @param ids List of lists of token IDs. Each element of `ids` corresponds to a list of tokens to mint for the corresponding address in `recipients`.
     */
    function mintBadgesBatch(address[] memory recipients, uint256[][] memory ids) external onlyRole(MINTER_ROLE) {
        if (recipients.length != ids.length) revert MismatchedInputLengths();
        if (recipients.length > 250) revert MintToManyAddresses();
        if (ids.length == 0) revert NoTokenIDsProvided();

        for (uint256 i = 0; i < recipients.length; i++) {
            mintBadges(recipients[i], ids[i]);
        }
    }

    /**
     * @dev Batch burning function that burns multiple types of tokens from multiple addresses.
     * Only callable by addresses with the MINTER_ROLE. Limits the batch to a maximum of 100 addresses.
     * @param accounts List of addresses to burn tokens from.
     * @param ids List of lists of token IDs. Each element of `ids` corresponds to a list of tokens to burn from the corresponding address in `accounts`.
     * @param amounts List of lists of amounts. Each element of `amounts` corresponds to the amount of tokens to burn for each ID in `ids`.
     */
    function burnBadgesBatch(address[] memory accounts, uint256[][] memory ids, uint256[][] memory amounts)
        external
        onlyRole(MINTER_ROLE)
    {
        if (accounts.length != ids.length || accounts.length != amounts.length) revert MismatchedInputLengths();
        if (accounts.length > 250) revert BurnTooManyAddresses();
        if (ids.length == 0) revert NoTokenIDsProvided();

        for (uint256 i = 0; i < accounts.length; i++) {
            if (ids[i].length != amounts[i].length) revert MismatchedInputLengths();
            _burnBatch(accounts[i], ids[i], amounts[i]);
        }
    }

    /**
     * @dev Authorization function for UUPS upgradeability.
     * @param newImplementation The address of the new contract implementation.
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}

    /**
     * @dev Returns whether the contract implements the interface defined by the id
     * @param interfaceId id of the interface to be checked.
     * @return true if the contract implements the interface defined by the id.
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC1155Upgradeable, AccessControlUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}

contract EngenBadgesV3 is EngenBadges {
    constructor() EngenBadges() {}
}
