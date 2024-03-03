// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

interface IBridger {
    /* ============ Errors ============ */
    error OnlySender();
    error OnlyOwner();
    error SignerNotEOA();
    error SignatureExpired();
    error InvalidNonce();
    error InvalidSigner();
    error InvalidAsset();
    error InvalidAmount();
    error SwapsDisabled();
    error NotEnoughEthToBridge();
    error GasFeeTooHigh();
    error ApprovalFailed();
    error SwapCallFailed();
    error SlippageError();

    /* ============ Structs ============ */

    struct SignatureData {
        address signer;
        address inputAsset;
        uint256 amount;
        address finalAsset;
        uint256 nonce;
        uint256 expiresAt;
        bytes signature;
    }

    struct SwapData {
        address spender;
        address swapTarget;
        bytes swapCallData;
        uint256 gasFee;
        uint256 minReceive;
    }

    struct Permit {
        address owner;
        address spender;
        uint256 value;
        uint256 nonce;
        uint256 deadline;
    }

    /* ============ State Change ============ */

    function depositETH(address _kintoWallet, address _finalAsset, SwapData calldata _swapData) external payable;

    function depositBySig(
        address _kintoWallet,
        SignatureData calldata _signatureData,
        SwapData calldata _swapData,
        bytes calldata _permitSignature
    ) external payable;

    function bridgeDeposits(address asset, uint256 maxGas, uint256 gasPriceBid, uint256 maxSubmissionCost)
        external
        payable;

    function emergencyExit(address _asset) external;

    function whitelistAssets(address[] calldata _assets, bool[] calldata _flags) external;

    function setSwapsEnabled(bool _swapsEnabled) external;

    function pause() external;

    function unpause() external;

    function setSenderAccount(address _senderAccount) external;

    /* ============ Basic Viewers ============ */

    function deposits(address _account, address _asset) external view returns (uint256);

    function nonces(address _account) external view returns (uint256);

    function domainSeparator() external view returns (bytes32);

    function allowedAssets(address) external view returns (bool);

    function swapsEnabled() external view returns (bool);

    function depositCount() external view returns (uint256);

    function l2Vault() external view returns (address);

    function senderAccount() external view returns (address);
}
