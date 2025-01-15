// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {IBridger} from "@kinto-core/interfaces/bridger/IBridger.sol";
import {IKintoID} from "@kinto-core/interfaces/IKintoID.sol";

import {
    IBridgerL2,
    SrcPreHookCallParams,
    DstPreHookCallParams,
    TransferInfo
} from "@kinto-core/interfaces/bridger/IBridgerL2.sol";
import "@kinto-core/interfaces/IKintoWalletFactory.sol";
import "@kinto-core/interfaces/IKintoWallet.sol";
import {IBridge} from "@kinto-core/interfaces/bridger/IBridge.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

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
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    /* ============ Constants ============ */

    /// @notice Treasure contract address.
    address public constant TREASURY = 0x793500709506652Fcc61F0d2D0fDa605638D4293;

    /* ============ State Variables ============ */
    /// @notice
    IKintoID public immutable kintoID;
    /// @notice
    IKintoWalletFactory public immutable walletFactory;
    /// @notice Mapping of all depositors by user address and asset address
    mapping(address => mapping(address => uint256)) public override deposits;
    /// @notice Deposit totals per asset
    mapping(address => uint256) public override depositTotals;
    /// @notice Count of deposits
    uint256 public override depositCount;
    /// @notice Enable or disable the locks
    bool public override unlocked;
    /// @notice Phase IV assets
    address[] public depositedAssets;
    /// @notice List of allowed vaults for the Bridge.
    mapping(address => bool) public bridgeVaults;
    // addresses that can receive assets while being not wallets on dstPreHookCall
    EnumerableSet.AddressSet private _receiveAllowlist;
    // addresses that can bypass funder whitelisted check on dstPreHookCall
    EnumerableSet.AddressSet private _senderAllowlist;

    /* ============ Constructor & Upgrades ============ */
    constructor(address _walletFactory, address _kintoID) {
        _disableInitializers();

        walletFactory = IKintoWalletFactory(_walletFactory);
        kintoID = IKintoID(_kintoID);
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

    function setBridgeVault(address vault, bool flag) external onlyOwner {
        bridgeVaults[vault] = flag;
    }

    /* ============ Withdraw  ============ */

    /**
     * @notice Internal function to handle withdrawals.
     * @param inputAsset Address of the input asset.
     * @param amount Amount of the input asset.
     * @param receiver Kinto Wallet Address on L2 where tokens will be deposited.
     * @param fee Amount paid as a fee.
     * @param bridgeData Data required for the bridge.
     */
    function withdrawERC20(
        address inputAsset,
        uint256 amount,
        address receiver,
        uint256 fee,
        IBridger.BridgeData calldata bridgeData
    ) external nonReentrant {
        if (walletFactory.walletTs(msg.sender) == 0) {
            revert InvalidWallet(msg.sender);
        }
        if (!kintoID.isKYC(IKintoWallet(msg.sender).owners(0))) {
            revert KYCRequired(receiver);
        }
        if (!IKintoWallet(msg.sender).isFunderWhitelisted(receiver)) {
            revert InvalidReceiver(receiver);
        }
        if (bridgeData.gasFee > address(this).balance) revert BalanceTooLow(bridgeData.gasFee, address(this).balance);
        // slither-disable-next-line arbitrary-send-erc20
        IERC20(inputAsset).safeTransferFrom(msg.sender, address(this), amount);
        if (fee > 0) {
            // slither-disable-next-line arbitrary-send-erc20
            IERC20(inputAsset).safeTransferFrom(msg.sender, TREASURY, fee);
        }

        if (amount == 0) revert InvalidAmount(0);
        if (bridgeVaults[bridgeData.vault] == false) revert InvalidVault(bridgeData.vault);

        // Approve max allowance to save on gas for future transfers
        if (IERC20(inputAsset).allowance(address(this), bridgeData.vault) < amount) {
            IERC20(inputAsset).safeApprove(bridgeData.vault, type(uint256).max);
        }

        // slither-disable-next-line arbitrary-send-eth
        IBridge(bridgeData.vault).bridge{value: bridgeData.gasFee}(
            receiver, amount, bridgeData.msgGasLimit, bridgeData.connector, bridgeData.execPayload, bridgeData.options
        );

        emit Withdraw(msg.sender, receiver, inputAsset, amount);
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

    /**
     * @dev Assign ENA rewards to users
     * Note: Only owner can call this function
     * @param users array of addresses of the users
     * @param amounts array of amounts of ENA to assign
     */
    function assignWstEthRefunds(address[] memory users, uint256[] memory amounts) external onlyOwner {
        for (uint256 i = 0; i < users.length; i++) {
            deposits[users[i]][0x6e316425A25D2Cf15fb04BCD3eE7c6325B240200] += amounts[i];
        }
    }

    /**
     * @dev Assign ENA rewards to users
     * Note: Only owner can call this function
     * @param users array of addresses of the users
     * @param amounts array of amounts of ENA to assign
     */
    function assignENARewards(address[] memory users, uint256[] memory amounts) external onlyOwner {
        for (uint256 i = 0; i < users.length; i++) {
            deposits[users[i]][0xE040001C257237839a69E9683349C173297876F0] = amounts[i];
        }
    }

    /* ============ Claim L2 ============ */

    /**
     * @dev Claim the commitment of a wallet
     * Note: This function has to be called via user operation from the wallet
     */
    function claimCommitment() external nonReentrant {
        if (walletFactory.walletTs(msg.sender) == 0) {
            revert InvalidWallet(msg.sender);
        }
        if (!unlocked) {
            revert NotUnlockedYet();
        }
        for (uint256 i = 0; i < depositedAssets.length; i++) {
            address currentAsset = depositedAssets[i];
            uint256 balance = deposits[msg.sender][currentAsset];
            if (balance > 0) {
                deposits[msg.sender][currentAsset] = 0;
                // slither-disable-next-line unchecked-transfer
                IERC20(_l2Address(currentAsset)).transfer(msg.sender, balance);
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

    /* ============ Hook ============ */

    function srcPreHookCall(SrcPreHookCallParams memory params_) external view {
        address sender = params_.msgSender;
        if (walletFactory.walletTs(sender) == 0) revert InvalidSender(sender);
        if (!kintoID.isKYC(IKintoWallet(sender).owners(0))) {
            revert KYCRequired(sender);
        }
    }

    function dstPreHookCall(DstPreHookCallParams memory params_) external view {
        address receiver = params_.transferInfo.receiver;
        address msgSender = abi.decode(params_.transferInfo.data, (address));

        if (!_receiveAllowlist.contains(receiver)) {
            if (walletFactory.walletTs(receiver) == 0) {
                revert InvalidReceiver(receiver);
            }

            if (!kintoID.isKYC(IKintoWallet(receiver).owners(0))) {
                revert KYCRequired(receiver);
            }
        }

        if (!_senderAllowlist.contains(msgSender)) {
            if (!IKintoWallet(receiver).isFunderWhitelisted(msgSender)) {
                revert SenderNotAllowed(msgSender);
            }
        }
    }

    function setReceiver(address[] memory receiver, bool[] memory allowed) external onlyOwner {
        for (uint256 index = 0; index < receiver.length; index++) {
            if (allowed[index]) {
                _receiveAllowlist.add(receiver[index]);
            } else {
                _receiveAllowlist.remove(receiver[index]);
            }
        }
        emit ReceiverSet(receiver, allowed);
    }

    function setSender(address[] memory sender, bool[] memory allowed) external onlyOwner {
        for (uint256 index = 0; index < sender.length; index++) {
            if (allowed[index]) {
                _senderAllowlist.add(sender[index]);
            } else {
                _senderAllowlist.remove(sender[index]);
            }
        }
        emit SenderSet(sender, allowed);
    }

    function receiveAllowlist() external view returns (address[] memory) {
        return _receiveAllowlist.values();
    }

    function senderAllowlist() external view returns (address[] memory) {
        return _senderAllowlist.values();
    }

    /* ============ Internals ============ */

    /**
     * @dev Returns actual L2 token representation address in Kinto
     */
    function _l2Address(address _asset) private pure returns (address) {
        if (_asset == 0x4190A8ABDe37c9A85fAC181037844615BA934711) return 0x5da1004F7341D510C6651C67B4EFcEEA76Cac0E8; // sDAI
        if (_asset == 0xF4d81A46cc3fCA44f88d87912A35E7fCC4B398ee) return 0x505de0f7a5d786063348aB5BC31e3a21344fA7B0; // sUSDe
        if (_asset == 0x6e316425A25D2Cf15fb04BCD3eE7c6325B240200) return 0x057e70cCa0dC435786a50FcF440bf8FcC1eEAf17; // wstETH
        if (_asset == 0xC60F14d95B87417BfD17a376276DE15bE7171d31) return 0x0Ee700095AeDFe0814fFf7d6DFD75461De8e2b19; // weETH
        return _asset;
    }
}

contract BridgerL2V9 is BridgerL2 {
    constructor(address walletFactory, address kintoID) BridgerL2(walletFactory, kintoID) {}
}
