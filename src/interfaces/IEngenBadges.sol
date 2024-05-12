// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

/**
 * @title IEngenBadges
 * @dev Interface for the EngenBadges contract.
 */
interface IEngenBadges {
    /**
     * @dev Initializes the contract with a specific URI for metadata and sets up roles.
     * @param uri The base URI for the ERC1155 token metadata.
     * @param initialAdmin The address to set as the initial admin.
     */
    function initialize(string calldata uri, address initialAdmin) external;

    /**
     * @dev Mints badges to a specified address with each ID only being minted once.
     * @param to The address to mint the badges to.
     * @param ids An array of token IDs to mint.
     */
    function mintBadges(address to, uint256[] calldata ids) external;

    /**
     * @dev Batch minting function that reuses mintBadges to mint multiple types of tokens to multiple addresses,
     * each ID being minted exactly once per specified recipient. Limits the batch to a maximum of 100 addresses.
     * @param recipients List of recipient addresses.
     * @param ids List of lists of token IDs. Each element of `ids` corresponds to a list of tokens to mint for the corresponding address in `recipients`.
     */
    function mintBadgesBatch(address[] calldata recipients, uint256[][] calldata ids) external;

    /**
     * @dev Returns whether the contract implements the interface defined by the id
     * @param interfaceId id of the interface to be checked.
     * @return true if the contract implements the interface defined by the id.
     */
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}
