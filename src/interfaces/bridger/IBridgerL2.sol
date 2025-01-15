// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

struct SrcPreHookCallParams {
    address connector;
    address msgSender;
    TransferInfo transferInfo;
}

struct DstPreHookCallParams {
    address connector;
    bytes connectorCache;
    TransferInfo transferInfo;
}

struct TransferInfo {
    address receiver;
    uint256 amount;
    bytes data;
}

interface IBridgerL2 {
    /* ============ Errors ============ */

    error KYCRequired(address user);
    error SenderNotAllowed(address wallet);
    error InvalidSender(address wallet);
    error InvalidReceiver(address wallet);
    error InvalidWallet(address wallet);
    error NotUnlockedYet();
    error Unauthorized();

    /// @notice The amount is invalid.
    /// @param amount The invalid amount.
    error InvalidAmount(uint256 amount);

    /// @notice The vault is not permitted.
    error InvalidVault(address vault);

    /// @notice Balance is too low for bridge operation.
    /// @param amount The amount required.
    error BalanceTooLow(uint256 amount, uint256 balance);

    /* ============ Events ============ */

    event Claim(address indexed wallet, address indexed asset, uint256 amount);

    event Withdraw(address indexed user, address indexed l1Address, address indexed inputAsset, uint256 amount);

    event ReceiverSet(address[] indexed receiver, bool[] allowed);

    event SenderSet(address[] indexed sender, bool[] allowed);

    event BridgeVaultSet(address[] indexed vault, bool[] flag);

    /* ============ Structs ============ */

    /* ============ State Change ============ */

    function writeL2Deposit(address depositor, address assetL2, uint256 amount) external;

    function unlockCommitments() external;

    function setDepositedAssets(address[] memory assets) external;

    function claimCommitment() external;

    /* ============ Basic Viewers ============ */

    function deposits(address _account, address _asset) external view returns (uint256);

    function depositTotals(address _asset) external view returns (uint256);

    function depositCount() external view returns (uint256);

    function getUserDeposits(address user) external view returns (uint256[] memory amounts);

    function getTotalDeposits() external view returns (uint256[] memory amounts);

    function unlocked() external view returns (bool);
}
