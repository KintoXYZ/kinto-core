// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {IKintoWallet} from "../interfaces/IKintoWallet.sol";

/// @custom:security-contact security@mamorilabs.com
contract EngenCredits is
    Initializable,
    ERC20Upgradeable,
    ERC20BurnableUpgradeable,
    OwnableUpgradeable,
    ERC20PermitUpgradeable,
    UUPSUpgradeable
{
    /// @dev EIP-20 token name for this token
    string private constant _NAME = "Engen Credits";

    /// @dev EIP-20 token symbol for this token
    string private constant _SYMBOL = "ENGEN";

    bool public transfersEnabled;
    bool public burnsEnabled;

    mapping(address => uint256) public phase1Override;

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
    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }

    /**
     * @dev Enable transfers of Engen tokens
     * @param _transfersEnabled True if transfers should be enabled
     */
    function setTransfersEnabled(bool _transfersEnabled) public onlyOwner {
        require(!transfersEnabled, "EC: Transfers Already enabled");
        transfersEnabled = _transfersEnabled;
    }

    /**
     * @dev Enable burning of Engen tokens
     * @param _burnsEnabled True if burning should be enabled
     */
    function setBurnsEnabled(bool _burnsEnabled) public onlyOwner {
        require(!burnsEnabled, "EC: Burns Already enabled");
        burnsEnabled = _burnsEnabled;
    }

    /**
     * @dev Set the phase 1 override for the user based on the time they joined
     * @param _wallets The wallet addresses of the users to override
     * @param _points The points to be set
     */
    function setPhase1Override(address[] calldata _wallets, uint256[] calldata _points) public onlyOwner {
        require(_wallets.length == _points.length, "EC: Invalid input");
        for (uint256 i = 0; i < _wallets.length; i++) {
            phase1Override[_wallets[i]] = _points[i];
        }
    }

    // ======= User Functions ==================

    /**
     * @dev Mint points for the Engen user based on their activity
     */
    function mintCredits() public {
        require(!transfersEnabled && !burnsEnabled, "EC: Mint not allowed after completion");
        uint256 points = calculatePoints(msg.sender);
        require(points > 0 && balanceOf(msg.sender) < points, "EC: No tokens to mint");
        _mint(msg.sender, points - balanceOf(msg.sender));
    }

    // ======= Phase Points ==================

    /**
     * @dev Calculates the points for the user from each phae in Engen
     * @param _wallet The wallet address of the user
     */
    function calculatePoints(address _wallet) public view returns (uint256) {
        uint256 points = 0;
        // Phase 1
        points = phase1Override[_wallet] > 0 ? phase1Override[_wallet] : 5;
        // Phase 2
        points += 5 + IKintoWallet(_wallet).signerPolicy() * 5;
        // TODO: Phase 3 & 4
        return points;
    }

    // ======= Private Functions ==================

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override(ERC20Upgradeable) {
        super._beforeTokenTransfer(from, to, amount);
        require(
            from == address(0) // mint
                || (to == address(0) && burnsEnabled) // burn
                || transfersEnabled,
            "EC: Transfers not enabled"
        );
    }
}
