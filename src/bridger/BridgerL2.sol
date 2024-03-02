// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../interfaces/IBridger.sol";
import "../interfaces/IKintoWalletFactory.sol";
import "../interfaces/IKintoWallet.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

/**
 * @title BridgerL2 - The vault that holds the bridged assets during Phase IV
 *
 */
contract BridgerL2 is Initializable, UUPSUpgradeable, OwnableUpgradeable, ReentrancyGuard, IBridgerL2 {
    using SignatureChecker for address;
    using ECDSA for bytes32;

    /* ============ Events ============ */
    event Deposit(
        address indexed from,
        address indexed wallet,
        address indexed asset,
        uint256 amount,
        address assetBought,
        uint256 amountBought
    );

    /* ============ Constants ============ */

    /* ============ State Variables ============ */
    IKintoWalletFactory public immutable walletFactory;

    /// @dev Mapping of all depositors by user address and asset address
    mapping(address => mapping(address => uint256)) public override deposits;
    /// @dev Deposit totals per asset
    mapping(address => uint256) public override depositTotals;
    /// @dev Count of deposits
    uint256 public depositCount;
    /// @dev Enable or disable the locks
    bool public unlocked;
    /// @dev Phase IV assets
    address[] allowedAssets;

    /* ============ Constructor & Upgrades ============ */
    constructor(address walletFactory) {
        _disableInitializers();
        walletFactory = IKintoWalletFactory(walletFactory);
    }

    /**
     * @dev Upgrade calling `upgradeTo()`
     */
    function initialize() external initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();
        _transferOwnership(msg.sender);
        unlocked = false;
    }

    /**
     * @dev Authorize the upgrade. Only by an owner.
     * @param newImplementation address of the new implementation
     */
    // This function is called by the proxy contract when the factory is upgraded
    function _authorizeUpgrade(address newImplementation) internal view override {
        (newImplementation);
        _onlyOwner();
    }

    /* ============ Privileged Functions ============ */

    function writeL2Deposit(address depositor, address assetL2, uint256 amount) external override {
        _onlyOwner();
        deposits[depositor][assetL2] += amount;
        depositTotals[assetL2] += amount;
    }

    function unlockCommitments() external override {
        _onlyOwner();
        unlocked = true;
    }

    /* ============ Claim L2 ============ */

    function claimCommitment(address kintoWallet) external nonReentrant {
        if (walletFactory.walletTs(kintoWallet) == 0 || IKintoWallet(wallet).owners(0) != msg.sender)
            revert InvalidWallet();
        if (!unlocked)
            revert NotUnlockedYet();
        for (uint i = 0; i < allowedAssets.length; i++) {
            address currentAsset = allowedAssets[i];
            uint256 balance = deposits[msg.sender][asset];
            if (balance > 0) {
                deposits[msg.sender][asset] = 0;
                IERC20(asset).transfer(kintoWallet, balance);
            }
        }
    }

    /* ============ Viewers ============ */
    
    function getUserDeposits() external view override returns (uint256[] amounts) {
        amounts = new uint[](allowedAssets.length);
        for (uint i = 0; i < allowedAssets.length; i++) {
            address currentAsset = allowedAssets[i];
            amounts[i] = deposits[msg.sender][asset];
        }
    }

    function getTotalDeposits() external view override returns (uint256[] amounts) {
        amounts = new uint[](allowedAssets.length);
        for (uint i = 0; i < allowedAssets.length; i++) {
            address currentAsset = allowedAssets[i];
            amounts[i] = depositTotals[asset];
        }
    }

    function _onlyOwner() {
        if (msg.sender != owner()) revert OnlyOwner();
    }
}

