// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {MathUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

/**
 * @title MorphoRepayment
 * @notice A contract that holds all the positions from Kinto wallets in the deprecated morpho vault.
 * @dev This contract implements a weighted timestamp staking mechanism for rewards distribution
 */
contract MorphoRepayment is Initializable, UUPSUpgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /* ============ Struct ============ */

    struct UserInfo {
        uint256 usdcLent; // 1e6 USDC
        uint256 collateralLocked; // 1e18 KINTO
        uint256 usdcBorrowed; // 1e6 USDC
        uint256 usdcRepaid; // 1e6 USDC
        bool isRepaid;
    }

    /* ============ Events ============ */

    event Repaid(address indexed user, uint256 amount);
    event FullyRepaid(address indexed user);
    event Recovered(address indexed user, uint256 amount);

    /* ============ State Variables ============ */
    IERC20Upgradeable public immutable collateralToken;
    IERC20Upgradeable public immutable debtToken;

    uint256 public constant TOTAL_COLLATERAL = 1343246113449322366913544; // 1.34M K e18
    uint256 public constant TOTAL_DEBT = 2641615234325; // 1e6 USDC
    uint256 public constant TOTAL_USDC_LENT = 2079948444941; // 1e6 USDC
    uint256 public constant BONUS_REPAYMENT = 1e17; // 10% bonus for repaying debt early
    uint256 public constant REPAYMENT_DEADLINE = 1763161200; // Nov 14th 2025 3pm PT
    uint256 public constant THREE_MONTHS = 7776000; // 90 days

    uint256 public totalCollateralUnlocked;
    uint256 public totalDebtRepaid;
    mapping(address => UserInfo) public userInfos;

    /* ============ Constructor ============ */

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(IERC20Upgradeable _collateralToken, IERC20Upgradeable _debtToken) {
        _disableInitializers();
        collateralToken = _collateralToken;
        debtToken = _debtToken;
    }

    function initialize() external initializer {
        __Ownable_init_unchained();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
    }

    /* ============ Proxy Upgrades ============ */

    // Required by UUPSUpgradeable
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /* ============ Set user info ============ */

    /**
     * @notice Set user info
     * @param _users The users to set info for
     * @param _userInfos The user info to set
     */
    function setUserInfo(address[] calldata _users, UserInfo[] calldata _userInfos) external onlyOwner {
        require(_users.length == _userInfos.length, "Length mismatch");
        for (uint256 i = 0; i < _users.length; i++) {
            UserInfo storage cur = userInfos[_users[i]];
            require(cur.usdcRepaid == 0 && !cur.isRepaid, "User immutable");
            userInfos[_users[i]] = _userInfos[i];
        }
    }

    /* ============ Repayment============ */

    /**
     * @notice Repay debt
     * @param _debtAmount The amount of debt to repay
     */
    function repayDebt(uint256 _debtAmount) external nonReentrant {
        UserInfo storage userInfo = userInfos[msg.sender];
        require(userInfo.usdcBorrowed - userInfo.usdcRepaid >= _debtAmount, "Not enough debt");
        require(!userInfo.isRepaid, "Has repaid already");
        require(block.timestamp <= REPAYMENT_DEADLINE, "Repayment deadline reached");

        if (_debtAmount > 0) {
            debtToken.safeTransferFrom(msg.sender, address(this), _debtAmount);
            userInfo.usdcRepaid += _debtAmount;
            totalDebtRepaid += _debtAmount;
        }

        if (userInfo.usdcRepaid == userInfo.usdcBorrowed) {
            userInfo.isRepaid = true;
            totalCollateralUnlocked += userInfo.collateralLocked;
            uint256 timeLeft = REPAYMENT_DEADLINE - block.timestamp;
            // prorata bonus based on time left, only 10% when left is 3 months
            uint256 collateralLockedBonusDen = _debtAmount * 1e12 * 3; // Using 3 as the conservative lock
            uint256 tenPct = MathUpgradeable.mulDiv(collateralLockedBonusDen, BONUS_REPAYMENT, 1e18);
            uint256 bonus = MathUpgradeable.mulDiv(tenPct, timeLeft, THREE_MONTHS);
            collateralToken.safeTransfer(msg.sender, userInfo.collateralLocked + bonus);
            userInfo.collateralLocked = 0;
            emit FullyRepaid(msg.sender);
        } else {
            emit Repaid(msg.sender, _debtAmount);
        }
    }

    /**
     * @notice Recover supplied USDC pro-rata based on total debt repaid
     */
    function recoverSuppliedUSDC() external nonReentrant {
        UserInfo storage userInfo = userInfos[msg.sender];
        uint256 lent = userInfo.usdcLent;
        require(lent > 0, "Not enough lent");
        require(block.timestamp >= REPAYMENT_DEADLINE, "Repayment deadline not reached");

        uint256 factor =
            totalDebtRepaid >= TOTAL_DEBT ? 1e18 : MathUpgradeable.mulDiv(totalDebtRepaid, 1e18, TOTAL_DEBT);
        uint256 amount = MathUpgradeable.mulDiv(lent, factor, 1e18);
        userInfo.usdcLent = factor == 1e18 ? 0 : lent - amount;
        debtToken.safeTransfer(msg.sender, amount);
        emit Recovered(msg.sender, amount);
    }
}
