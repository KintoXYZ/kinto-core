// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title WildcatRepayment
 * @notice A contract that holds all the positions from Wildcat lenders so they can recover a portion of their principal as estipulated.
 * @dev This contract is owned by the Kinto foundation.
 */
contract WildcatRepayment is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /* ============ Struct ============ */

    struct UserInfo {
        uint256 firstClaim; // 1e6 USDC
        uint256 secondClaim; // 1e6 USDC
        bool claimedFirst;
        bool claimedSecond;
    }

    /* ============ Events ============ */

    event ClaimedFirst(address indexed user, uint256 amount);
    event ClaimedSecond(address indexed user, uint256 amount);
    event EmergencyRecovered(uint256 amount);

    /* ============ State Variables ============ */
    IERC20 public constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    address public constant OWNER = 0x2E7111Ef34D39b36EC84C656b947CA746e495Ff6;
    bool public secondPeriodOpen = false;

    mapping(address => UserInfo) public userInfos;

    /* ============ Constructor ============ */

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        userInfos[0x5b1b1Ef66214fe163B602FC5B81903906A786211] =
            UserInfo({firstClaim: 250000000000, secondClaim: 130000000000, claimedFirst: false, claimedSecond: false});
        userInfos[0x4086f688855dcAe061e7f68fc181566FFfa856eA] =
            UserInfo({firstClaim: 100396500000, secondClaim: 52206180000, claimedFirst: false, claimedSecond: false});
        userInfos[0xE1f8aFc92644Bfe77080D7DCb0f936F578E00F53] =
            UserInfo({firstClaim: 9300000000, secondClaim: 4836000000, claimedFirst: false, claimedSecond: false});
        userInfos[0x3a00568BAb4D610C2e97C1AAD1959af4e2AA15a0] =
            UserInfo({firstClaim: 4999100130, secondClaim: 2599532068, claimedFirst: false, claimedSecond: false});
        userInfos[0xdaE0424Fd265b683EF1a2525aCeBa37d001565B7] =
            UserInfo({firstClaim: 4990500000, secondClaim: 2595060000, claimedFirst: false, claimedSecond: false});
        userInfos[0xFE10dFDc18789eb5F3a8FE4fE9FBc3e17E075191] =
            UserInfo({firstClaim: 1500000000, secondClaim: 780000000, claimedFirst: false, claimedSecond: false});
        userInfos[0x702d2f5d52811d08A2211B49a8524355B9AEEe6C] =
            UserInfo({firstClaim: 1248500000, secondClaim: 649220000, claimedFirst: false, claimedSecond: false});
        userInfos[0xC4293F52633b3603E65e9B4C2B4D4F40EecCA91C] =
            UserInfo({firstClaim: 599000000, secondClaim: 311480000, claimedFirst: false, claimedSecond: false});
        userInfos[0x5F5F90E8359131daCAec572F5128220362Be1E71] =
            UserInfo({firstClaim: 500000000, secondClaim: 260000000, claimedFirst: false, claimedSecond: false});
        userInfos[0x660ad4B5A74130a4796B4d54BC6750Ae93C86e6c] =
            UserInfo({firstClaim: 497500000, secondClaim: 258700000, claimedFirst: false, claimedSecond: false});
        userInfos[0xd61daEBC28274d1feaAf51F11179cd264e4105fB] =
            UserInfo({firstClaim: 444933950, secondClaim: 231365654, claimedFirst: false, claimedSecond: false});
        userInfos[0x9194eFdF03174a804f3552F4F7B7A4bB74BaDb7F] =
            UserInfo({firstClaim: 250000000, secondClaim: 130000000, claimedFirst: false, claimedSecond: false});
        userInfos[0xac0BA417f93682CCC27723bbFAD2128bfcff6Dc6] =
            UserInfo({firstClaim: 250000000, secondClaim: 130000000, claimedFirst: false, claimedSecond: false});
        userInfos[0x5b105130f6E50ECdaD810a6BD29c267ADf57d211] =
            UserInfo({firstClaim: 2500, secondClaim: 1300, claimedFirst: false, claimedSecond: false});

        _transferOwnership(OWNER);
    }

    /* ============ Claims============ */

    /**
     * @notice Accept terms and claims first period
     */
    function acceptAndClaimFirst() external nonReentrant {
        require(!userInfos[msg.sender].claimedFirst, "Already claimed");
        require(userInfos[msg.sender].firstClaim > 0, "Nothing to claim");
        userInfos[msg.sender].claimedFirst = true;
        USDC.safeTransfer(msg.sender, userInfos[msg.sender].firstClaim);
        emit ClaimedFirst(msg.sender, userInfos[msg.sender].firstClaim);
    }

    /**
     * @notice Accepts terms and claims second period
     */
    function acceptAndClaimSecond() external nonReentrant {
        require(secondPeriodOpen, "Second period not open");
        require(!userInfos[msg.sender].claimedSecond, "Already claimed");
        require(userInfos[msg.sender].secondClaim > 0, "Nothing to claim");
        userInfos[msg.sender].claimedSecond = true;
        USDC.safeTransfer(msg.sender, userInfos[msg.sender].secondClaim);
        emit ClaimedSecond(msg.sender, userInfos[msg.sender].secondClaim);
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
        require(!_userInfo.claimedFirst && !_userInfo.claimedSecond, "User immutable");
        userInfos[_user] = _userInfo;
    }

    function startSecondPeriod() external onlyOwner {
        secondPeriodOpen = true;
    }
}
