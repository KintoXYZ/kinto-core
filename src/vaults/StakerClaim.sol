// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title StakerClaim (Arbitrum)
 * @notice A contract that allows stakers to keep the last airdrop and their staked tokens
 * @dev Only users with at least 5 staked tokens are included
 */
contract StakerClaim is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /* ============ Struct ============ */

    struct UserInfo {
        uint256 amount; // 1e18 staked kinto
        bool claimed;
    }

    /* ============ Events ============ */

    event Claimed(address indexed user, uint256 amount);
    event EmergencyRecovered(uint256 amount);

    /* ============ State Variables ============ */
    IERC20 public constant USDC = IERC20(0xaf88d065e77c8cC2239327C5EDb3A432268e5831);
    IERC20 public constant KINTO = IERC20(0x6bA19Ee69D5DDe3aB70185C801fA404F66feDB58);
    address public constant OWNER = 0x8bFe32Ac9C21609F45eE6AE44d4E326973700614;

    mapping(address => UserInfo) public userInfos;
    uint256 public eraPriceFactor = 1;

    /* ============ Constructor ============ */

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _transferOwnership(OWNER);
    }

    /* ============ Claims============ */

    /**
     * @notice Accept terms and claims the USDC and the staked KINTO
     */
    function acceptAndClaim() external nonReentrant {
        require(!userInfos[msg.sender].claimed, "Already claimed");
        require(userInfos[msg.sender].amount > 0, "Nothing to claim");
        userInfos[msg.sender].claimed = true;
        KINTO.safeTransfer(msg.sender, userInfos[msg.sender].amount);
        // Adjusts decimals and ratio in 10e6 decimals
        uint256 eraAmountIn6Dec = userInfos[msg.sender].amount / 1e9 / 3177;
        USDC.safeTransfer(msg.sender, eraAmountIn6Dec * eraPriceFactor);
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

    function setEraPriceFactor(uint256 _eraPriceFactor) external onlyOwner {
        eraPriceFactor = _eraPriceFactor;
    }
}
