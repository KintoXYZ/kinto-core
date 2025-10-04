// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title KintoLeftOver
 * @notice A contract that holds users balances in USDC that did not withdraw.
 * @dev Only users with at least $50 are included
 */
contract KintoLeftOver is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /* ============ Struct ============ */

    struct UserInfo {
        uint256 amount; // 1e6 USDC
        bool claimed;
    }

    /* ============ Events ============ */

    event Claimed(address indexed user, uint256 amount);
    event EmergencyRecovered(uint256 amount);

    /* ============ State Variables ============ */
    IERC20 public constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    address public constant OWNER = 0x2E7111Ef34D39b36EC84C656b947CA746e495Ff6;

    mapping(address => UserInfo) public userInfos;

    /* ============ Constructor ============ */

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _transferOwnership(OWNER);
    }

    /* ============ Claims============ */

    /**
     * @notice Accept terms and claims first period
     */
    function acceptAndClaim() external nonReentrant {
        require(!userInfos[msg.sender].claimed, "Already claimed");
        require(userInfos[msg.sender].amount > 0, "Nothing to claim");
        userInfos[msg.sender].claimed = true;
        USDC.safeTransfer(msg.sender, userInfos[msg.sender].amount);
        emit Claimed(msg.sender, userInfos[msg.sender].amount);
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
     * @notice Set user info
     * @param _user The users to update
     * @param _userInfo The info to set
     */
    function updateUserInfo(address _user, UserInfo calldata _userInfo) external onlyOwner {
        require(!userInfos[_user].claimed, "User immutable");
        userInfos[_user] = _userInfo;
    }

    /**
     * @notice Set users info
     * @param _users The users to set info for
     * @param _amounts The amounts to set for the users
     */
    function setUsersInfo(address[] calldata _users, uint256[] calldata _amounts) external onlyOwner {
        require(_users.length == _amounts.length, "Invalid params");
        for (uint256 i = 0; i < _users.length; i++) {
            require(userInfos[_users[i]].claimed == false, "User already claimed");
            userInfos[_users[i]] = UserInfo({amount: _amounts[i], claimed: false});
        }
    }
}
