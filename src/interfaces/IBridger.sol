// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IWETH is IERC20 {
    function deposit() external payable;

    function withdraw(uint256 wad) external;
}

interface IDAI {
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

interface IsUSDe is IERC20 {
    function deposit(uint256 amount, address recipient) external returns (uint256);
}

interface IL1GatewayRouter {
    function outboundTransfer(
        address _token,
        address _to,
        uint256 _amount,
        uint256 _maxGas,
        uint256 _gasPriceBid,
        bytes calldata _data
    ) external payable;
}

interface IBridger {
    /* ============ Errors ============ */
    error OnlySender();
    error OnlyOwner();
    error SignatureExpired();
    error InvalidNonce();
    error InvalidSigner();
    error InvalidAsset();
    error InvalidAmount();
    error InvalidAssets();
    error SwapsDisabled();
    error NotEnoughEthToBridge();
    error GasFeeTooHigh();
    error ApprovalFailed();
    error SwapCallFailed();
    error SlippageError();
    error OnlyExchangeProxy();

    /* ============ Structs ============ */

    struct SignatureData {
        address kintoWallet; // Kinto Wallet Address on L2 where tokens will be deposited
        address signer;
        address inputAsset;
        address finalAsset;
        uint256 amount;
        uint256 nonce;
        uint256 expiresAt;
        bytes signature;
        SwapData swapData; // Struct with all the required information to swap the tokens
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

    function depositBySig(SignatureData calldata _signatureData, bytes calldata _permitSignature) external payable;

    function bridgeDeposits(address asset, uint256 maxGas, uint256 gasPriceBid, uint256 maxSubmissionCost)
        external
        payable;

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

    function exchangeProxy() external view returns (address);
}
