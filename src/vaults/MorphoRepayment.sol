// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {IERC20MetadataUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {MathUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {IKintoWalletFactory} from "@kinto-core/interfaces/IKintoWalletFactory.sol";

/**
 * @title MorphoRepayment
 * @notice A contract that holds all the positions from Kinto wallets in the deprecated morpho vault.
 * @dev This contract implements a weighted timestamp staking mechanism for rewards distribution
 */
contract MorphoRepayment is Initializable, UUPSUpgradeable, OwnableUpgradeable {
    using SafeERC20Upgradeable for ERC20Upgradeable;

    /* ============ Struct ============ */

    struct UserInfo {
        uint256 usdcLent;
        uint256 collateralLocked;
        uint256 usdcBorrowed;
        uint256 usdcRepaid;
        bool isRepaid;
    }

    /* ============ Events ============ */

    event Repaid(address indexed user, uint256 amount);
    event FullyRepaid(address indexed user);

    /* ============ State Variables ============ */
    ERC20Upgradeable public immutable collateralToken;
    ERC20Upgradeable public immutable debtToken;
    IKintoWalletFactory public immutable factory;

    uint256 public constant TOTAL_COLLATERAL = 1e24;
    uint256 public constant TOTAL_DEBT = 25e23;
    uint256 public constant BONUS_REPAYMENT = 1e17; // 10% bonus for repaying debt early
    uint256 public constant REPAYMENT_DEADLINE = 1763161200; // Nov 14th 2025 3pm PT
    uint256 public constant THREE_MONTHS = 7776000; // 90 days

    uint256 public totalCollateralUnlocked;
    uint256 public totalDebtRepaid;
    mapping(address => UserInfo) public userInfos;

    /* ============ Constructor ============ */

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(ERC20Upgradeable _collateralToken, ERC20Upgradeable _debtToken, IKintoWalletFactory _factory) {
        _disableInitializers();
        collateralToken = _collateralToken;
        debtToken = _debtToken;
        factory = _factory;
    }

    function initialize() external initializer {
        __Ownable_init_unchained();
        __UUPSUpgradeable_init();
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
        for (uint256 i = 0; i < _users.length; i++) {
            userInfos[_users[i]] = _userInfos[i];
        }
    }

    /* ============ Repayment============ */

    /**
     * @notice Repay debt
     * @param _debtAmount The amount of debt to repay
     */
    function repayDebt(uint256 _debtAmount) external {
        UserInfo storage userInfo = userInfos[msg.sender];
        require(factory.getWalletTimestamp(msg.sender) > 0, "Not a Kinto wallet");
        require(userInfo.usdcBorrowed - userInfo.usdcRepaid >= _debtAmount, "Not enough debt");
        require(!userInfo.isRepaid, "Has repaid already");

        debtToken.safeTransferFrom(msg.sender, address(this), _debtAmount);
        userInfo.usdcRepaid += _debtAmount;
        totalDebtRepaid += _debtAmount;

        if (userInfo.usdcRepaid == userInfo.usdcBorrowed) {
            userInfo.isRepaid = true;
            totalCollateralUnlocked += userInfo.collateralLocked;
            userInfo.collateralLocked = 0;
            uint256 timeLeft = REPAYMENT_DEADLINE - block.timestamp;
            // prorata bonus based on time left, only 10% when left is 3 months
            uint256 bonus = userInfo.collateralLocked * BONUS_REPAYMENT / 1e18 * timeLeft / THREE_MONTHS;
            collateralToken.safeTransfer(msg.sender, userInfo.collateralLocked + bonus);
            emit FullyRepaid(msg.sender);
        } else {
            emit Repaid(msg.sender, _debtAmount);
        }
    }
}
