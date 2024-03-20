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
 * @dev This contract is used to hold the assets that are bridged from L1 to L2 during Phase IV
 * The assets are held in this contract until the wallet claims them at the end of phase IV.
 * Only Kinto wallets can claim the assets and only after the commitments are unlocked.
 *
 */
contract BridgerL2 is Initializable, UUPSUpgradeable, OwnableUpgradeable, ReentrancyGuard, IBridgerL2 {
    using SignatureChecker for address;
    using ECDSA for bytes32;

    /* ============ Events ============ */
    event Claim(address indexed wallet, address indexed asset, uint256 amount);

    /* ============ Constants ============ */

    /* ============ State Variables ============ */
    IKintoWalletFactory public immutable walletFactory;

    /// @dev Mapping of all depositors by user address and asset address
    mapping(address => mapping(address => uint256)) public override deposits;
    /// @dev Deposit totals per asset
    mapping(address => uint256) public override depositTotals;
    /// @dev Count of deposits
    uint256 public override depositCount;
    /// @dev Enable or disable the locks
    bool public override unlocked;
    /// @dev Phase IV assets
    address[] public depositedAssets;

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
    function _authorizeUpgrade(address newImplementation) internal view override onlyOwner {
        (newImplementation);
    }

    /* ============ Privileged Functions ============ */

    /**
     * @dev Sets the deposit on the L2 to be claimed by the wallet at the end of phase IV
     * Note: Only owner or factory can call this function
     * @param walletAddress address of the wallet
     * @param assetL2 address of the asset on the L2
     * @param amount amount of the asset to receive
     */
    function writeL2Deposit(address walletAddress, address assetL2, uint256 amount) external override {
        if (msg.sender != owner() && msg.sender != address(walletFactory)) {
            revert Unauthorized();
        }
        deposits[walletAddress][assetL2] += amount;
        depositTotals[assetL2] += amount;
        depositCount++;
    }

    /**
     * @dev Unlock the commitments
     * Note: Only owner can call this function
     */
    function unlockCommitments() external override onlyOwner {
        unlocked = true;
    }

    /**
     * @dev Set the assets that are deposited
     * Note: Only owner can call this function
     * @param assets array of addresses of the assets
     */
    function setDepositedAssets(address[] memory assets) external override onlyOwner {
        depositedAssets = assets;
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
        for (uint256 i = 0; i < depositedAssets.length; i++) {
            address currentAsset = depositedAssets[i];
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
        amounts = new uint256[](depositedAssets.length);
        for (uint256 i = 0; i < depositedAssets.length; i++) {
            address currentAsset = depositedAssets[i];
            amounts[i] = deposits[user][currentAsset];
        }
    }

    /**
     * @dev Get the total number of deposits of all assets
     */
    function getTotalDeposits() external view override returns (uint256[] memory amounts) {
        amounts = new uint256[](depositedAssets.length);
        for (uint256 i = 0; i < depositedAssets.length; i++) {
            address currentAsset = depositedAssets[i];
            amounts[i] = depositTotals[currentAsset];
        }
    }
}

contract BridgerL2V3 is BridgerL2 {
    constructor(address _walletFactory) BridgerL2(_walletFactory) {}
}
