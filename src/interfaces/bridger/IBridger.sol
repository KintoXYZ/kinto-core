// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title IDAI
 * @notice Interface for DAI token operations.
 */
interface IDAI {
    /**
     * @notice Permit the spender to spend the specified amount of tokens on behalf of the owner.
     * @param holder The address of the token holder.
     * @param spender The address of the spender.
     * @param nonce The current nonce of the token holder.
     * @param expiry The timestamp at which the permit expires.
     * @param allowed Whether the spender is allowed to spend the tokens.
     * @param v The recovery byte of the signature.
     * @param r Half of the ECDSA signature pair.
     * @param s Half of the ECDSA signature pair.
     */
    function permit(
        address holder,
        address spender,
        uint256 nonce,
        uint256 expiry,
        bool allowed,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
}

/**
 * @title IsUSDe
 * @notice Interface for sUSDe token operations.
 */
interface IsUSDe is IERC20 {
    /**
     * @notice Deposit USDe tokens and receive sUSDe tokens.
     * @param amount Amount of USDe tokens to deposit.
     * @param recipient Address to receive the sUSDe tokens.
     * @return Amount of sUSDe tokens received.
     */
    function deposit(uint256 amount, address recipient) external returns (uint256);
}

/**
 * @title IBridger
 * @notice Interface for Bridger contract operations.
 */
interface IBridger {
    /* ============ Errors ============ */
    /// @notice Only the owner can call this function.
    error OnlyOwner();
    /// @notice The signature has expired.
    error SignatureExpired();
    /// @notice The nonce is invalid.
    error InvalidNonce();
    /// @notice The signer is invalid.
    error InvalidSigner();
    /// @notice The amount is invalid.
    /// @param amount The invalid amount.
    error InvalidAmount(uint256 amount);
    /// @notice Failed to stake ETH.
    error FailedToStakeEth();
    /// @notice Slippage error occurred.
    /// @param boughtAmount The amount bought.
    /// @param minReceive The minimum amount to receive.
    error SlippageError(uint256 boughtAmount, uint256 minReceive);

    /* ============ Structs ============ */

    /**
     * @title SignatureData
     * @notice Struct to hold signature data for deposits.
     */
    struct SignatureData {
        /// @notice Kinto Wallet Address on L2 where tokens will be deposited.
        address kintoWallet;
        /// @notice Address of the signer.
        address signer;
        /// @notice Address of the input asset.
        address inputAsset;
        /// @notice Address of the final asset.
        address finalAsset;
        /// @notice Amount of the input asset.
        uint256 amount;
        /// @notice Minimum amount of finalAsset to receive.
        uint256 minReceive;
        /// @notice Nonce for replay protection.
        uint256 nonce;
        /// @notice Expiration time of the signature.
        uint256 expiresAt;
        /// @notice Signature to be verified.
        bytes signature;
    }

    /**
     * @title Permit
     * @notice Struct to hold permit data.
     */
    struct Permit {
        /// @notice Address of the owner.
        address owner;
        /// @notice Address of the spender.
        address spender;
        /// @notice Value to be spent.
        uint256 value;
        /// @notice Nonce for replay protection.
        uint256 nonce;
        /// @notice Deadline for the permit.
        uint256 deadline;
    }

    /**
     * @title BridgeData
     * @notice Struct to hold bridge data.
     */
    struct BridgeData {
        /// @notice Address of the vault.
        address vault;
        /// @notice Gas fee for the bridge.
        uint256 gasFee;
        /// @notice Gas limit for the message.
        uint256 msgGasLimit;
        /// @notice Address of the connector.
        address connector;
        /// @notice Execution payload for the bridge.
        bytes execPayload;
        /// @notice Options for the bridge.
        bytes options;
    }

    /* ============ State Change ============ */

    /**
     * @notice Deposit tokens by signature.
     * @param permitSignature Signature for permit.
     * @param signatureData Data for the deposit.
     * @param swapCallData Data required for the swap.
     * @param bridgeData Data required for the bridge.
     */
    function depositBySig(
        bytes calldata permitSignature,
        IBridger.SignatureData calldata signatureData,
        bytes calldata swapCallData,
        BridgeData calldata bridgeData
    ) external payable;

    /**
     * @notice Deposit ERC20 tokens.
     * @param inputAsset Address of the input asset.
     * @param amount Amount of the input asset.
     * @param kintoWallet Kinto Wallet Address on L2 where tokens will be deposited.
     * @param finalAsset Address of the final asset.
     * @param minReceive Minimum amount to receive after swap.
     * @param swapCallData Data required for the swap.
     * @param bridgeData Data required for the bridge.
     */
    function depositERC20(
        address inputAsset,
        uint256 amount,
        address kintoWallet,
        address finalAsset,
        uint256 minReceive,
        bytes calldata swapCallData,
        BridgeData calldata bridgeData
    ) external payable;

    /**
     * @notice Deposit ETH.
     * @param amount Amount of ETH to deposit.
     * @param kintoWallet Kinto Wallet Address on L2 where tokens will be deposited.
     * @param finalAsset Address of the final asset.
     * @param minReceive Minimum amount to receive after swap.
     * @param swapCallData Data required for the swap.
     * @param bridgeData Data required for the bridge.
     */
    function depositETH(
        uint256 amount,
        address kintoWallet,
        address finalAsset,
        uint256 minReceive,
        bytes calldata swapCallData,
        BridgeData calldata bridgeData
    ) external payable;

    /**
     * @notice Pause the contract.
     */
    function pause() external;

    /**
     * @notice Unpause the contract.
     */
    function unpause() external;

    /**
     * @notice Set the sender account.
     * @param senderAccount Address of the sender account.
     */
    function setSenderAccount(address senderAccount) external;

    /* ============ View ============ */

    /**
     * @notice Get the nonce for an account.
     * @param account Address of the account.
     * @return Nonce of the account.
     */
    function nonces(address account) external view returns (uint256);

    /**
     * @notice Get the domain separator.
     * @return Domain separator.
     */
    function domainSeparator() external view returns (bytes32);

    /**
     * @notice Get the sender account address.
     * @return Sender account address.
     */
    function senderAccount() external view returns (address);

    /**
     * @notice Get the swap router address.
     * @return Swap router address.
     */
    function swapRouter() external view returns (address);
}
