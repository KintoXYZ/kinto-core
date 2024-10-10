// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC721} from "@openzeppelin-5.0.1/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin-5.0.1/contracts/access/Ownable.sol";
import {EIP712} from "@openzeppelin-5.0.1/contracts/utils/cryptography/EIP712.sol";
import {ERC721Votes} from "@openzeppelin-5.0.1/contracts/token/ERC721/extensions/ERC721Votes.sol";

/**
 * @title NioGuardians
 * @notice A contract for managing Nio Guardian NFTs with voting capabilities
 */
contract NioGuardians is ERC721, Ownable, EIP712, ERC721Votes {
    /**
     * @notice Thrown when attempting to transfer a token
     */
    error OnlyMintOrBurn();
    /**
     * @notice Thrown when attempting to delegate votes
     */
    error NoDelegate();

    /**
     * @notice Initializes the NioGuardians contract
     * @param initialOwner The address of the initial contract owner
     */
    constructor(address initialOwner)
        ERC721("Nio Guardians", "NIO")
        Ownable(initialOwner)
        EIP712("Nio Guardians", "1")
    {}

    /**
     * @notice Mints a new Nio Guardian NFT
     * @param to The address to mint the token to
     * @param tokenId The ID of the token to mint
     */
    function mint(address to, uint256 tokenId) public onlyOwner {
        _safeMint(to, tokenId);
        // delegate the votes on a mint to a holder
        _delegate(to, to);
    }

    /**
     * @notice Burns a Nio Guardian NFT
     * @param tokenId The ID of the token to burn
     */
    function burn(uint256 tokenId) public onlyOwner {
        _burn(tokenId);
    }

    /**
     * @notice Returns the current timestamp
     * @return The current block timestamp as a uint48
     */
    function clock() public view override returns (uint48) {
        return uint48(block.timestamp);
    }

    /**
     * @notice Returns the clock mode for the contract
     * @return A string indicating the clock mode is timestamp-based
     */
    // solhint-disable-next-line func-name-mixedcase
    function CLOCK_MODE() public pure override returns (string memory) {
        return "mode=timestamp";
    }

    /**
     * @notice Internal function to update token ownership
     * @param to The address to transfer the token to
     * @param tokenId The ID of the token being transferred
     * @param auth The address authorized to make the transfer
     * @return The address the token was transferred from
     */
    function _update(address to, uint256 tokenId, address auth)
        internal
        override(ERC721, ERC721Votes)
        returns (address)
    {
        address from = super._update(to, tokenId, auth);

        if (from != address(0) && to != address(0)) revert OnlyMintOrBurn();

        return from;
    }

    /**
     * @notice Overrides the delegate function to prevent delegation
     */
    function delegate(address) public pure override {
        revert NoDelegate();
    }

    /**
     * @notice Overrides the delegate function to prevent delegation
     */
    function delegateBySig(address, uint256, uint256, uint8, bytes32, bytes32) public pure override {
        revert NoDelegate();
    }

    /**
     * @notice Internal function to increase the balance of an account
     * @param account The address of the account to increase the balance for
     * @param value The amount to increase the balance by
     */
    function _increaseBalance(address account, uint128 value) internal override(ERC721, ERC721Votes) {
        super._increaseBalance(account, value);
    }

    /**
     * @notice Checks if a token with the given ID exists
     * @param tokenId The ID of the token to check
     * @return bool True if the token exists, false otherwise
     */
    function exists(uint256 tokenId) external view returns (bool) {
        return _ownerOf(tokenId) != address(0);
    }
}
