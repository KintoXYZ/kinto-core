// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

/**
 * @title KintoToken
 * @dev KintoToken is an ERC20 token with governance features and a time bomb.
 * It is meant to be used as the main governance token for the Kinto platform.
 */
contract KintoToken is ERC20, Ownable, ERC20Burnable, ERC20Permit, ERC20Votes {
    /// @dev EIP-20 token name for this token
    string private constant _NAME = "Kinto Token";
    /// @dev EIP-20 token symbol for this token
    string private constant _SYMBOL = "KINTO";
    /// @dev Initial supply minted at contract deployment
    uint256 public constant INITIAL_SUPPLY = 3_567_000e18;
    /// @dev EIP-20 Max token supply ever
    uint256 public constant MAX_SUPPLY = 15_000_000e18;
    /// @dev Governance time bomb
    uint256 public constant GOVERNANCE_RELEASE_DEADLINE = 1714489; // May 1st UTC
    /// @dev Timestamp of the contract deployment
    uint256 public immutable deployedAt;

    constructor() ERC20(_NAME, _SYMBOL) ERC20Permit(_NAME) {
        deployedAt = block.timestamp;
        _mint(msg.sender, INITIAL_SUPPLY);
    }

    /**
     * @dev Mint new tokens
     * @param to The address to which the minted tokens will be transferred
     * @param amount The amount of tokens to mint
     */
    function mint(address to, uint256 amount) public onlyOwner {
        require(block.timestamp >= GOVERNANCE_RELEASE_DEADLINE, "Not transferred to governance yet");
        require(totalSupply() + amount <= MAX_SUPPLY, "Cannot exceed max supply");
        _mint(to, amount);
    }

    // Need to override this internal function to call super._mint
    function _mint(address to, uint256 amount) internal override(ERC20, ERC20Votes) {
        super._mint(to, amount);
    }

    // Need to override this internal function to disable burning
    function _burn(address, /* to */ uint256 /* amount */ ) internal pure override(ERC20, ERC20Votes) {
        revert("Burn is not allowed");
    }

    // Need to override this because of the imports
    function _afterTokenTransfer(address from, address to, uint256 amount) internal override(ERC20, ERC20Votes) {
        super._afterTokenTransfer(from, to, amount);
    }
}
