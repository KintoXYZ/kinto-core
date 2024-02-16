// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

/**
 * @title KintoToken - To be deployed on ETH mainnet
 * @dev KintoToken is an ERC20 token with governance features and a time bomb.
 * To be deployed on ETH Mainnet.
 * It is meant to be used as the main governance token for the Kinto platform.
 * It is created with an initial supply and a max supply cap.
 * The max supply cap is reached after 10 years with a 5% inflation rate.
 */
contract KintoToken is ERC20, Ownable, ERC20Burnable, ERC20Permit, ERC20Votes {
    /// @dev EIP-20 token name for this token
    string private constant _NAME = "Kinto Token";
    /// @dev EIP-20 token symbol for this token
    string private constant _SYMBOL = "KINTO";
    /// @dev Initial supply minted at contract deployment
    uint256 public constant SEED_TOKENS = 3_567_000e18;
    /// @dev Max supply at launch
    uint256 public constant MAX_SUPPLY_LAUNCH = 10_000_000e18;
    /// @dev EIP-20 Max token supply ever
    uint256 public constant MAX_CAP_SUPPLY_EVER = 15_000_000e18;
    /// @dev Governance time bomb
    uint256 public constant GOVERNANCE_RELEASE_DEADLINE = 1714489; // May 1st UTC
    /// @dev Timestamp of the contract deployment
    uint256 public immutable deployedAt;

    /// @dev Address of the mining contract
    address public miningContract;

    /// @dev Address of the vesting contract
    address public vestingContract;

    /// @dev Whether token transfers are enabled
    bool public tokenTransfersEnabled;

    constructor() ERC20(_NAME, _SYMBOL) ERC20Permit(_NAME) {
        deployedAt = block.timestamp;
        _mint(msg.sender, SEED_TOKENS);
    }

    /**
     * @dev Mint new tokens
     * @param to The address to which the minted tokens will be transferred
     * @param amount The amount of tokens to mint
     */
    function mint(address to, uint256 amount) public onlyOwner {
        require(block.timestamp >= GOVERNANCE_RELEASE_DEADLINE, "Not transferred to governance yet");
        require(totalSupply() + amount <= getSupplyCap(), "Cannot exceed max supply");
        _mint(to, amount);
    }

    /**
     * @dev Enable token transfers
     */
    function enableTokenTransfers() public onlyOwner {
        require(block.timestamp >= GOVERNANCE_RELEASE_DEADLINE && !tokenTransfersEnabled, "Cannot enable transfers yet");
        tokenTransfersEnabled = true;
    }

    /**
     * @dev Set the vesting contract address
     * @param _vestingContract The address of the vesting contract
     */
    function setVestingContract(address _vestingContract) public onlyOwner {
        require(_vestingContract != address(0), "Invalid address");
        vestingContract = _vestingContract;
    }

    /**
     * @dev Set the mining contract address
     * @param _miningContract The address of the mining contract
     */
    function setMiningContract(address _miningContract) public onlyOwner {
        require(_miningContract != address(0), "Invalid address");
        miningContract = _miningContract;
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

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override {
        super._beforeTokenTransfer(from, to, amount);
        require(
            from == address(0) || from == address(miningContract) || to == address(miningContract)
                || from == address(vestingContract) || to == address(vestingContract) || tokenTransfersEnabled,
            "Kinto Tokens Transfers are disabled"
        );
    }

    /**
     * @dev Returns the max supply at the current time
     */
    function getSupplyCap() public view returns (uint256) {
        if (block.timestamp < GOVERNANCE_RELEASE_DEADLINE) {
            return SEED_TOKENS;
        }
        if (block.timestamp <= deployedAt + 365 days) {
            return MAX_SUPPLY_LAUNCH;
        }
        uint256 yearsPassed = (block.timestamp - deployedAt) / 365 days;
        if (yearsPassed >= 10) {
            return MAX_CAP_SUPPLY_EVER;
        }
        // 5% initial supply inflation max
        return MAX_SUPPLY_LAUNCH + (yearsPassed * 500_000e18);
    }
}
