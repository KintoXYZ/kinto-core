// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../interfaces/IBridger.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

interface IWETH is IERC20 {
    function deposit() external payable;

    function withdraw(uint256 wad) external;
}

interface IL1GatewayRouter {
    function outboundTransfer(
        address _token,
        address _to,
        uint256 _amount,
        uint256 _maxGas,
        uint256 _gasPriceBid,
        bytes calldata _data
    ) external;
}

/**
 * @title Bridger - To be deployed on ETH mainnet and on Kinto L2
 *
 */
contract Bridger is Initializable, UUPSUpgradeable, OwnableUpgradeable, ReentrancyGuard, IBridger {
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
    address public constant L2_VAULT = address(1);
    address public constant SENDER_ACCOUNT = address(1);

    IWETH public constant WETH = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    address public constant sDAI = 0x83F20F44975D03b1b09e64809B757c47f942BEeA;
    address public constant sUSDe = 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497;
    address public constant wstETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address public constant weETH = 0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee;

    IL1GatewayRouter public constant L1GatewayRouter = IL1GatewayRouter(0xD9041DeCaDcBA88844b373e7053B4AC7A3390D60);
    address public constant standardGateway = 0x7870D5398DB488c669B406fBE57b8d05b6A35e42;

    /* ============ State Variables ============ */
    bytes32 public immutable override domainSeparator;

    /// @dev Mapping of input assets that are allowed
    mapping(address => bool) public override allowedAssets;
    /// @dev Mapping of all depositors by user address and asset address
    mapping(address => mapping(address => uint256)) public override deposits;
    /// @dev We include a nonce in every hashed message, and increment the nonce as part of a
    /// state-changing operation, so as to prevent replay attacks, i.e. the reuse of a signature.
    mapping(address => uint256) public override nonces;
    /// @dev Count of deposits
    uint256 public depositCount;

    /* ============ Constructor & Upgrades ============ */
    constructor() {
        _disableInitializers();
        domainSeparator = _domainSeparator();
    }

    /**
     * @dev Upgrade calling `upgradeTo()`
     */
    function initialize() external initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();
        _transferOwnership(msg.sender);
    }

    /**
     * @dev Authorize the upgrade. Only by an owner.
     * @param newImplementation address of the new implementation
     */
    // This function is called by the proxy contract when the factory is upgraded
    function _authorizeUpgrade(address newImplementation) internal view override {
        (newImplementation);
        if (msg.sender != owner()) revert OnlyOwner();
    }

    /* ============ Deposit methods ============ */

    /**
     * @dev Deposit the specified amount of tokens in to the Kinto L2
     * @param _kintoWallet Kinto Wallet Address on L2 where tokens will be deposited
     * @param _signatureData Struct with all the required information to deposit via signature
     * @param _swapData Struct with all the required information to swap the tokens
     * @param _permitSignature Signature to be recovered to allow the spender to spend the tokens
     */
    function depositBySig(
        address _kintoWallet,
        IBridger.SignatureData calldata _signatureData,
        IBridger.SwapData calldata _swapData,
        bytes calldata _permitSignature
    ) external override onlySignerVerified(_signatureData) onlyPrivileged {
        _isFinalAssetAllowed(_signatureData.finalAsset);
        if (_signatureData.inputAsset != _signatureData.finalAsset && !allowedAssets[_signatureData.inputAsset]) {
            revert InvalidAsset();
        }
        _permit(
            _signatureData.signer,
            _signatureData.inputAsset,
            _signatureData.amount,
            _signatureData.expiresAt,
            _permitSignature
        );
        _deposit(_signatureData.signer, _signatureData.inputAsset, _signatureData.amount);
        _swap(
            _signatureData.signer,
            _kintoWallet,
            _signatureData.inputAsset,
            _signatureData.amount,
            _signatureData.finalAsset,
            _swapData
        );
        nonces[_signatureData.signer]++;
    }

    /**
     * @dev Deposit the specified amount of ETH in to the Kinto L2 as finalAsset
     * @param _kintoWallet Kinto Wallet Address on L2 where tokens will be deposited
     * @param _finalAsset Asset to depositInto
     * @param _swapData Struct with all the required information to swap the tokens
     */
    function depositETH(address _kintoWallet, address _finalAsset, IBridger.SwapData calldata _swapData)
        external
        payable
        override
        nonReentrant
    {
        _isFinalAssetAllowed(_finalAsset);
        if (msg.value < 0.1 ether) revert InvalidAmount();
        WETH.deposit{value: msg.value}();
        deposits[msg.sender][address(WETH)] += msg.value;
        _swap(msg.sender, _kintoWallet, address(WETH), msg.value, _finalAsset, _swapData);
    }

    /**
     * @dev Bridges deposits in bulk every hour to the L2
     */
    function bridgeDeposits(address asset, uint256 maxGas, uint256 gasPriceBid, uint256 maxSubmissionCost)
        external
        override
        onlyPrivileged
    {
        // Approve the gateway to get the tokens
        IERC20(asset).approve(standardGateway, type(uint256).max);
        // Bridge to Kinto L2 using standard bridge
        // https://github.com/OffchainLabs/arbitrum-sdk/blob/a0c71474569cd6d7331d262f2fd969af953f24ae/src/lib/assetBridger/erc20Bridger.ts#L592C1-L596C10
        L1GatewayRouter.outboundTransfer(
            asset, //token
            L2_VAULT, // Account to be credited with the tokens in L2
            IERC20(asset).balanceOf(address(this)), // Amount of tokens to bridge
            maxGas, // Max gas deducted from user’s L2 balance to cover the execution in L2
            gasPriceBid, // Gas price for the execution in L2
            abi.encode(
                maxSubmissionCost, // Max gas deducted from user's L2 balance to cover base submission fee. Usually 0
                bytes(""), // bytes extraData hook
                (maxGas * gasPriceBid) + maxSubmissionCost // Total gas deducted from user’s L2 balance
            )
        );
    }

    /* ============ Privileged methods ============ */

    /**
     * @dev Whitelist the assets that can be deposited
     * @param _assets array of addresses of the assets to be whitelisted
     */
    function whitelistAssets(address[] calldata _assets, bool[] calldata _flags) external override onlyOwner {
        require(_assets.length == _flags.length, "Invalid input");
        for (uint256 i = 0; i < _assets.length; i++) {
            allowedAssets[_assets[i]] = _flags[i];
        }
    }

    /**
     * @dev Withdraw all the ETH or a specific asset from the contract in an emergency
     * @param _asset address of the asset to be withdrawn. If address(0), withdraws all the ETH
     */
    function emergencyExit(address _asset) external override onlyOwner {
        if (_asset == address(0)) {
            payable(msg.sender).transfer(address(this).balance);
        } else {
            IERC20(_asset).transfer(msg.sender, IERC20(_asset).balanceOf(address(this)));
        }
    }

    /* ============ Private methods ============ */

    function _swap(
        address _sender,
        address _kintoWallet,
        address _inputAsset,
        uint256 _amount,
        address _finalAsset,
        IBridger.SwapData calldata _swapData
    ) private {
        // swap using 0x
        uint256 amountBought = _amount;
        if (_inputAsset != _finalAsset) {
            amountBought = _fillQuote(
                IERC20(_inputAsset),
                IERC20(_finalAsset),
                payable(_swapData.spender),
                payable(_swapData.swapTarget),
                _swapData.swapCallData
            );
        }
        depositCount++;
        emit Deposit(_sender, _kintoWallet, _inputAsset, _amount, _finalAsset, amountBought);
    }

    /**
     * @dev Permit the spender to spend the specified amount of tokens on behalf of the owner
     * @param spender sender of the tokens
     * @param asset address of the token
     * @param amount amount of tokens
     * @param expiresAt deadline for the signature
     * @param signature signature to be recovered
     */
    function _permit(address spender, address asset, uint256 amount, uint256 expiresAt, bytes memory signature)
        private
    {
        // (uint8 v, bytes32 r, bytes32 s) = abi.decode(signature, (uint8, bytes32, bytes32));
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := mload(add(signature, 0x20))
            s := mload(add(signature, 0x40))
        }
        v = uint8(signature[64]); // last byte
        ERC20Permit(asset).permit(spender, address(this), amount, expiresAt, v, r, s);
    }

    /**
     * @dev Deposit the specified amount of tokens
     * @param sender sender of the tokens
     * @param asset address of the token
     * @param amount amount of tokens
     */
    function _deposit(address sender, address asset, uint256 amount) private {
        if (
            amount == 0 || IERC20(asset).allowance(sender, address(this)) < amount
                || IERC20(asset).balanceOf(sender) < amount
        ) revert InvalidAmount();
        IERC20(asset).transferFrom(sender, address(this), amount);
        deposits[sender][asset] += amount;
    }

    /**
     * @dev Swaps ERC20->ERC20 tokens held by this contract using a 0x-API quote.
     */
    function _fillQuote(
        // The `sellTokenAddress` field from the API response.
        IERC20 sellToken,
        // The `buyTokenAddress` field from the API response.
        IERC20 buyToken,
        // The `allowanceTarget` field from the API response.
        address spender,
        // The `to` field from the API response.
        address payable swapTarget,
        // The `data` field from the API response.
        bytes calldata swapCallData
    ) private returns (uint256) {
        // Checks that the swapTarget is actually the address of 0x ExchangeProxy
        // require(swapTarget == exchangeProxy, "Target not ExchangeProxy");

        // Track our balance of the buyToken to determine how much we've bought.
        uint256 boughtAmount = buyToken.balanceOf(address(this));

        // Give `spender` an infinite allowance to spend this contract's `sellToken`.
        require(sellToken.approve(spender, type(uint256).max), "Failed to approve spender");
        // Call the encoded swap function call on the contract at `swapTarget`,
        // passing along any ETH attached to this function call to cover protocol fees.
        (bool success,) = swapTarget.call{value: msg.value}(swapCallData);
        require(success, "SWAP_CALL_FAILED");
        // Keep the protocol fee refunds given that we are paying for gas
        // Use our current buyToken balance to determine how much we've bought.
        boughtAmount = buyToken.balanceOf(address(this)) - boughtAmount;
        return boughtAmount;
    }

    receive() external payable {}

    function _isFinalAssetAllowed(address _asset) private pure {
        if (
            _asset != address(sDAI) && _asset != address(sUSDe) && _asset != address(wstETH) && _asset != address(weETH)
                && _asset != address(0)
        ) revert InvalidAsset();
    }

    /* ============ Signature Recovery ============ */

    /**
     * @dev Check that the signature is valid and it has not used yet
     * @param _signature signature to be recovered.
     */
    modifier onlySignerVerified(IBridger.SignatureData calldata _signature) {
        if (block.timestamp >= _signature.expiresAt) revert SignatureExpired();
        if (nonces[_signature.signer] != _signature.nonce) revert InvalidNonce();

        // Ensure signer is an EOA
        uint256 size;
        address signer = _signature.signer;
        assembly {
            size := extcodesize(signer)
        }
        if (size > 0) revert SignerNotEOA();

        bytes32 eip712MessageHash =
            keccak256(abi.encodePacked("\x19\x01", domainSeparator, _hashSignatureData(_signature)));
        if (!_signature.signer.isValidSignatureNow(eip712MessageHash, _signature.signature)) revert InvalidSigner();
        _;
    }

    modifier onlyPrivileged() {
        if (msg.sender != owner() && msg.sender != SENDER_ACCOUNT) revert OnlyOwner();
        _;
    }

    /* ============ EIP-712 Helpers ============ */

    function _domainSeparator() internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("Bridger")), // this contract's name
                keccak256(bytes("1")), // version
                _getChainID(),
                address(this)
            )
        );
    }

    function _hashSignatureData(SignatureData memory signatureData) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                keccak256(
                    "SignatureData(address signer,address inputAsset,uint256 amount,address finalAsset,uint256 nonce,uint256 expiresAt)"
                ),
                signatureData.signer,
                signatureData.inputAsset,
                signatureData.amount,
                signatureData.finalAsset,
                signatureData.nonce,
                signatureData.expiresAt
            )
        );
    }

    function _getChainID() internal view returns (uint256) {
        uint256 chainID;
        assembly {
            chainID := chainid()
        }
        return chainID;
    }
}
