// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

contract KintoToken is ERC20, Ownable, ERC20Burnable, ERC20Permit, ERC20Votes {
    /// @dev EIP-20 token name for this token
    string private constant _NAME = "Kinto Token";
    /// @dev EIP-20 token symbol for this token
    string private constant _SYMBOL = "KINTO";
    /// @dev
    uint256 public constant INITIAL_SUPPLY = 10_000_000e18;
    uint256 public constant MAX_SUPPLY = 15_000_000e18;
    uint256 public constant GOVERNANCE_RELEASE_DEADLINE = 1714489; // May 1st UTC

    uint256 public immutable deployedAt;

    constructor() ERC20(_NAME, _SYMBOL) ERC20Permit(_NAME) {
        deployedAt = block.timestamp;
        _mint(msg.sender, INITIAL_SUPPLY);
    }

    function mint(address to, uint256 amount) public onlyOwner {
        require(block.timestamp >= GOVERNANCE_RELEASE_DEADLINE, "Not transferred to governance yet");
        require(totalSupply() + amount <= MAX_SUPPLY, "Cannot exceed max supply");
        _mint(to, amount);
    }

    function _mint(address to, uint256 amount) internal override(ERC20, ERC20Votes) {
        super._mint(to, amount);
    }

    function _burn(address, /* to */ uint256 /* amount */ ) internal pure override(ERC20, ERC20Votes) {
        revert("Burn is not allowed");
    }

    function _afterTokenTransfer(address from, address to, uint256 amount) internal override(ERC20, ERC20Votes) {
        super._afterTokenTransfer(from, to, amount);
    }
}
