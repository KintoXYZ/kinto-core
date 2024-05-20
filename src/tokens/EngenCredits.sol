// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "../interfaces/IEngenCredits.sol";

import {IKintoWallet} from "../interfaces/IKintoWallet.sol";

/// @custom:security-contact security@mamorilabs.com
contract EngenCredits is
    Initializable,
    ERC20Upgradeable,
    ERC20BurnableUpgradeable,
    OwnableUpgradeable,
    ERC20PermitUpgradeable,
    UUPSUpgradeable,
    IEngenCredits
{
    /// @dev EIP-20 token name for this token
    string private constant _NAME = "Engen Credits";

    /// @dev EIP-20 token symbol for this token
    string private constant _SYMBOL = "ENGEN";

    bool public override transfersEnabled;
    bool public override burnsEnabled;

    mapping(address => uint256) public override earnedCredits;
    uint256 public override totalCredits;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() external initializer {
        __ERC20_init(_NAME, _SYMBOL);
        __ERC20Burnable_init();
        __Ownable_init();
        __ERC20Permit_init(_NAME);
        __UUPSUpgradeable_init();
        transfersEnabled = false;
        burnsEnabled = false;
    }

    // ======= Privileged Functions ==================

    /**
     * @dev Mint Engen tokens
     * @param to The address of the user to mint tokens for
     * @param amount The amount of tokens to mint
     */
    function mint(address to, uint256 amount) external override onlyOwner {
        _mint(to, amount);
    }

    /**
     * @dev Enable transfers of Engen tokens
     * @param _transfersEnabled True if transfers should be enabled
     */
    function setTransfersEnabled(bool _transfersEnabled) external override onlyOwner {
        if (transfersEnabled) revert TransfersAlreadyEnabled();
        transfersEnabled = _transfersEnabled;
    }

    /**
     * @dev Enable burning of Engen tokens
     * @param _burnsEnabled True if burning should be enabled
     */
    function setBurnsEnabled(bool _burnsEnabled) external override onlyOwner {
        if (burnsEnabled) revert BurnsAlreadyEnabled();
        burnsEnabled = _burnsEnabled;
    }

    /**
     * @dev Set the engen credits that a wallet has earned
     * @param _wallets The wallet addresses of the users
     * @param _points The credits earned by each user
     */
    function setCredits(address[] calldata _wallets, uint256[] calldata _points) external override onlyOwner {
        if (_wallets.length != _points.length) revert LengthMismatch();
        for (uint256 i = 0; i < _wallets.length; i++) {
            totalCredits -= earnedCredits[_wallets[i]];
            earnedCredits[_wallets[i]] = _points[i];
            totalCredits += _points[i];
        }
    }

    // ======= Votes Functions ==================

    /**
     * @dev Get the past votes of a user. Always hardcoded to credits earned
     * @param account The address of the user
     * hparam timepoint The timepoint to get the votes at
     * @return The number of votes the user had at the timepoint
     */
    function getPastVotes(address account, uint256 /* timepoint */ ) external view override returns (uint256) {
        return earnedCredits[account];
    }

    /**
     * @dev Get the total supply of votes at a timepoint. Always hardcoded to total credits
     * hparam timepoint The timepoint to get the votes at
     * @return The total number of votes at the timepoint
     */
    function getPastTotalSupply(uint256 /* timepoint */ ) external view override returns (uint256) {
        return totalCredits;
    }

    /**
     * @dev Get the clock for the votes
     * @return The current timepoint
     */
    function clock() external view override returns (uint48) {
        return uint48(block.timestamp);
    }

    /**
     * @dev Get the clock mode for the votes. Always hardcoded to timestamp
     * @return The clock mode
     */
    function CLOCK_MODE() external pure override returns (string memory) {
        return "mode=timestamp";
    }

    // ======= User Functions ==================

    /**
     * @dev Mint points for the Engen user based on their activity
     */
    function mintCredits() external override {
        if (transfersEnabled || burnsEnabled) revert MintNotAllowed();
        uint256 points = earnedCredits[msg.sender];
        if (points == 0 || balanceOf(msg.sender) >= points) revert NoTokensToMint();
        _mint(msg.sender, points - balanceOf(msg.sender));
    }

    // ======= Private Functions ==================

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override(ERC20Upgradeable) {
        super._beforeTokenTransfer(from, to, amount);
        if (
            from != address(0) // mint
                && (to != address(0) || !burnsEnabled) // burn
                && !transfersEnabled
        ) revert TransfersNotEnabled();
    }
}

contract EngenCreditsV3 is EngenCredits {
    constructor() EngenCredits() {}
}
