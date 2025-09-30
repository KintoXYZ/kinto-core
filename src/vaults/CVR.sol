// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title CVR
 * @notice A contract that holds users balances in USDC that did not withdraw.
 * @dev Only users with at least $50 are included
 */
contract CVR is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /* ============ Struct ============ */

    struct FounderDonation {
        uint256 amount; // 1e6 USDC
        bool claimed;
    }

    /* ============ Events ============ */

    event DonationClaimed(address indexed user, uint256 amount);
    event EmergencyRecovered(uint256 amount);
    event CVREntrySignedUp(address indexed user);

    /* ============ State Variables ============ */
    IERC20 public constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    address public constant OWNER = 0x2E7111Ef34D39b36EC84C656b947CA746e495Ff6;

    mapping(address => FounderDonation) public founderDonations;
    mapping(address => bool) public signedUp;

    /* ============ Constructor ============ */

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _transferOwnership(OWNER);
    }

    /* ============ Claims============ */

    /**
     * @notice Claim Founder Donation
     */
    function acceptAndClaim() external nonReentrant {
        require(!founderDonations[msg.sender].claimed, "Already claimed");
        require(founderDonations[msg.sender].amount > 0, "Nothing to claim");
        founderDonations[msg.sender].claimed = true;
        signedUp[msg.sender] = true;
        USDC.safeTransfer(msg.sender, founderDonations[msg.sender].amount);
        emit DonationClaimed(msg.sender, founderDonations[msg.sender].amount);
        emit CVREntrySignedUp(msg.sender);
    }

    /**
     * @notice Sign up for CVR
     */
    function acceptAndSignupCVREntry() external nonReentrant {
        require(!signedUp[msg.sender], "Already signed up");
        signedUp[msg.sender] = true;
        emit CVREntrySignedUp(msg.sender);
    }

    /* ============ Admin functions ============ */

    /**
     * @notice Emergency recover by the safe in case of emergency
     */
    function emergencyRecover() external onlyOwner nonReentrant {
        uint256 amount = USDC.balanceOf(address(this));
        USDC.safeTransfer(OWNER, amount);
        emit EmergencyRecovered(amount);
    }

    /**
     * @notice Set donation info
     * @param _user The user to receive a donation
     * @param _donationInfo The info to set for the user
     */
    function updateDonationInfo(address _user, FounderDonation calldata _donationInfo) external onlyOwner {
        require(!founderDonations[_user].claimed, "User immutable");
        founderDonations[_user] = _donationInfo;
    }

    /**
     * @notice Set donations info
     * @param _users The users to set donations for
     * @param _amounts The amounts to set for the users
     */
    function setUsersDonationInfo(address[] calldata _users, uint256[] calldata _amounts) external onlyOwner {
        require(_users.length == _amounts.length, "Invalid params");
        for (uint256 i = 0; i < _users.length; i++) {
            require(founderDonations[_users[i]].claimed == false, "User already claimed");
            founderDonations[_users[i]] = FounderDonation({amount: _amounts[i], claimed: false});
        }
    }
}
