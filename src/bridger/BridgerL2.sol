// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../interfaces/IBridgerL2.sol";
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
    event Claim(
        address indexed wallet,
        address indexed asset,
        uint256 amount
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
    constructor(address _walletFactory) {
        _disableInitializers();
        walletFactory = IKintoWalletFactory(_walletFactory);
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

    /**
     * @dev Sets the deposit on the L2 to be claimed by the wallet at the end of phase IV
     * Note: Only owner can call this function
     * @param walletAddress address of the wallet
     * @param assetL2 address of the asset on the L2
     * @param amount amount of the asset to receive
     */
    function writeL2Deposit(address walletAddress, address assetL2, uint256 amount) external override {
        _onlyOwner();
        deposits[walletAddress][assetL2] += amount;
        depositTotals[assetL2] += amount;
        depositCount++;
    }

    /**
     * @dev Unlock the commitments
     * Note: Only owner can call this function
     */
    function unlockCommitments() external override {
        _onlyOwner();
        unlocked = true;
    }

    /* ============ Claim L2 ============ */

    /**
     * @dev Claim the commitment of a wallet
     * Note: This function has to be called via user operation from the wallet
     */
    function claimCommitment() external nonReentrant {
        if (walletFactory.walletTs(msg.sender) == 0) {
            revert InvalidWallet();
        }
        if (!unlocked) {
            revert NotUnlockedYet();
        }
        for (uint256 i = 0; i < allowedAssets.length; i++) {
            address currentAsset = allowedAssets[i];
            uint256 balance = deposits[msg.sender][currentAsset];
            if (balance > 0) {
                deposits[msg.sender][currentAsset] = 0;
                IERC20(currentAsset).transfer(msg.sender, balance);
                emit Claim(msg.sender, currentAsset, balance);
            }
        }
    }

    /* ============ Viewers ============ */

    /**
     * @dev Get the total number of deposits from an user address
     * @param user address of the user
     */
    function getUserDeposits(address user) external view override returns (uint256[] memory amounts) {
        amounts = new uint256[](allowedAssets.length);
        for (uint256 i = 0; i < allowedAssets.length; i++) {
            address currentAsset = allowedAssets[i];
            amounts[i] = deposits[user][currentAsset];
        }
    }

    /**
     * @dev Get the total number of deposits of all assets
     */
    function getTotalDeposits() external view override returns (uint256[] memory amounts) {
        amounts = new uint256[](allowedAssets.length);
        for (uint256 i = 0; i < allowedAssets.length; i++) {
            address currentAsset = allowedAssets[i];
            amounts[i] = depositTotals[currentAsset];
        }
    }

    function _onlyOwner() private view {
        if (msg.sender != owner()) revert OnlyOwner();
    }
}
