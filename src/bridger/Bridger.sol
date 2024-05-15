// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

import {MessageHashUtils} from "@openzeppelin-5.0.1/contracts/utils/cryptography/MessageHashUtils.sol";

import {IBridger, IL1GatewayRouter, IWETH, IDAI, IsUSDe} from "@kinto-core/interfaces/IBridger.sol";

/**
 * @title Bridger - To be deployed on ETH mainnet.
 * Users can deposit tokens in to the Kinto L2 using this contract.
 * The contract will swap the tokens if needed and deposit them in to the Kinto L2
 * in batches every few hours.
 * Users can select one of 4 final assets to deposit in to the Kinto L2:
 * sDAI, sUSDe, wstETH, weETH.
 * Swaps are initially disabled but will be performed using 0x API.
 * Input assets are only assets that support ERC20 permit + ETH.
 * If depositing ETH and final asset is wstETH, it is just converted to wstETH (no swap is done).
 * If depositing ETH and final asset is other than wstETH, ETH is first wrapped to WETH and then swapped to desired asset.
 * If USDe is provided, it is directly staked.
 */
contract Bridger is
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuard,
    PausableUpgradeable,
    IBridger
{
    using Address for address;
    using SignatureChecker for address;
    using ECDSA for bytes32;
    using SafeERC20 for IERC20;

    /* ============ Events ============ */
    event Bridged(
        address indexed from,
        address indexed wallet,
        address indexed asset,
        uint256 amount,
        address assetBought,
        uint256 amountBought
    );

    /* ============ Constants & Immutables ============ */
    IL1GatewayRouter public constant L1GatewayRouter = IL1GatewayRouter(0xD9041DeCaDcBA88844b373e7053B4AC7A3390D60);
    address public constant standardGateway = 0x7870D5398DB488c669B406fBE57b8d05b6A35e42;

    address public constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    IWETH public immutable WETH;
    address public immutable DAI;
    address public immutable USDe;
    address public immutable sUSDe;
    address public immutable wstETH;

    bytes32 public immutable override domainSeparator;
    address public immutable override l2Vault;
    /// @notice The address of the 0x exchange proxy through which swaps are executed.
    address public immutable exchangeProxy;

    /* ============ State Variables ============ */

    address public override senderAccount;

    /// @dev Mapping of input assets that are allowed
    mapping(address => bool) public override allowedAssets;
    /// @dev DEPRECATED
    mapping(address => mapping(address => uint256)) public override deposits;
    /// @dev We include a nonce in every hashed message, and increment the nonce as part of a
    /// state-changing operation, so as to prevent replay attacks, i.e. the reuse of a signature.
    mapping(address => uint256) public override nonces;
    /// @dev Count of deposits
    uint256 public depositCount;
    /// @dev DEPRECATED
    bool public swapsEnabled;
    /// @dev Mapping of final assets that are allowed
    mapping(address => bool) public override finalAllowedAssets;

    /* ============ Modifiers ============ */
    modifier onlyPrivileged() {
        if (msg.sender != owner() && msg.sender != senderAccount) revert OnlyOwner();
        _;
    }

    /* ============ Constructor & Upgrades ============ */

    /**
     * @dev Initializes the contract by setting the exchange proxy address.
     * @param _exchangeProxy The address of the exchange proxy to be used for token swaps.
     */
    constructor(
        address _exchangeProxy,
        address weth,
        address dai,
        address usde,
        address sUsde,
        address wstEth
    ) {
        _disableInitializers();
        domainSeparator = _domainSeparatorV4();

        exchangeProxy = _exchangeProxy;

        WETH = IWETH(weth);
        DAI = dai;
        USDe = usde;
        sUSDe = sUSDe;
        wstETH = wstEth;
    }

    /**
     * @dev Upgrade calling `upgradeTo()`
     */
    function initialize(address _senderAccount) external initializer {
        __UUPSUpgradeable_init();
        __Ownable_init();
        __Pausable_init();

        _transferOwnership(msg.sender);
        senderAccount = _senderAccount;
    }

    /**
     * @dev Authorize the upgrade. Only by an owner.
     * @param newImplementation address of the new implementation
     */
    function _authorizeUpgrade(address newImplementation) internal view override onlyOwner {
        (newImplementation);
    }

    /* ============ Pause and Unpause ============ */

    /**
     * @dev Pause the contract. Only owner
     */
    function pause() external override onlyOwner {
        _pause();
    }

    /**
     * @dev Unpause the contract. Only owner
     */
    function unpause() external override onlyOwner {
        _unpause();
    }

    /**
     * @dev Set the sender account. Only owner
     * @param _senderAccount address of the sender account
     */
    function setSenderAccount(address _senderAccount) external override onlyOwner {
        senderAccount = _senderAccount;
    }

    /* ============ Public ============ */

    /**
     * @dev Deposit the specified amount of tokens in to the Kinto L2
     * @param depositData Struct with all the required information to deposit via signature
     * @param permitSignature, Signature to be recovered to allow the spender to spend the tokens
     */
    function depositBySig(
        bytes calldata permitSignature,
        IBridger.SignatureData calldata depositData,
        bytes calldata swapCallData
    ) external payable override whenNotPaused nonReentrant onlyPrivileged onlySignerVerified(depositData) {
        _checkFinalAsset(depositData.finalAsset);

        if (depositData.inputAsset != depositData.finalAsset && !allowedAssets[depositData.inputAsset]) {
            revert InvalidInputAsset(depositData.inputAsset);
        }

        if (
            depositData.amount == 0
                || IERC20(depositData.inputAsset).allowance(depositData.signer, address(this)) < depositData.amount
                || IERC20(depositData.inputAsset).balanceOf(depositData.signer) < depositData.amount
        ) revert InvalidAmount(depositData.amount);

        // slither-disable-next-line arbitrary-send-erc20
        IERC20(depositData.inputAsset).safeTransferFrom(depositData.signer, address(this), depositData.amount);

        _permit(
            depositData.signer,
            depositData.inputAsset,
            depositData.amount,
            depositData.expiresAt,
            ERC20Permit(depositData.inputAsset).nonces(depositData.signer),
            permitSignature
        );

        uint256 amountBought = _swap(
            depositData.kintoWallet,
            depositData.inputAsset,
            depositData.finalAsset,
            depositData.amount,
            depositData.minReceive,
            swapCallData
        );

        nonces[depositData.signer]++;

        emit Bridged(depositData.signer, depositData.kintoWallet, depositData.inputAsset, depositData.amount, depositData.finalAsset, amountBought);
    }

    /**
     * @dev Deposit the specified amount of ETH in to the Kinto L2 as finalAsset
     * @param kintoWallet Kinto Wallet Address on L2 where tokens will be deposited
     * @param finalAsset Asset to depositInto
     * @param swapCallData Struct with all the required information to swap the tokens
     */
    function depositETH(
        address kintoWallet,
        address finalAsset,
        uint256 minReceive,
        bytes calldata swapCallData
    ) external payable override whenNotPaused nonReentrant {
        _checkFinalAsset(finalAsset);

        if (msg.value < 0.1 ether) revert InvalidAmount(msg.value);

        uint256 amountBought = _swap(kintoWallet, ETH, finalAsset, msg.value, minReceive, swapCallData);

        emit Bridged(msg.sender, kintoWallet, ETH, msg.value, finalAsset, amountBought);
    }

    /**
     * @dev Bridges deposits in bulk every hour to the L2
     */
    function bridgeDeposits(address asset, uint256 maxGas, uint256 gasPriceBid, uint256 maxSubmissionCost)
        external
        payable
        onlyPrivileged
    {
        // Approve the gateway to get the tokens
        uint256 gasCost = (maxGas * gasPriceBid) + maxSubmissionCost;
        if (address(this).balance + msg.value < gasCost) revert NotEnoughEthToBridge();
        if (IERC20(asset).allowance(address(this), standardGateway) < type(uint256).max) {
            if (asset == wstETH) IERC20(asset).safeApprove(standardGateway, 0); // wstETH decreases allowance and does not allow non-zero to non-zero approval
            IERC20(asset).safeApprove(standardGateway, type(uint256).max);
        }
        // Bridge to Kinto L2 using standard bridge
        // https://github.com/OffchainLabs/arbitrum-sdk/blob/a0c71474569cd6d7331d262f2fd969af953f24ae/src/lib/assetBridger/erc20Bridger.ts#L592C1-L596C10
        L1GatewayRouter.outboundTransfer{value: gasCost}(
            asset, //token
            l2Vault, // Account to be credited with the tokens in L2
            IERC20(asset).balanceOf(address(this)), // Amount of tokens to bridge
            maxGas, // Max gas deducted from user’s L2 balance to cover the execution in L2
            gasPriceBid, // Gas price for the execution in L2
            abi.encode(
                maxSubmissionCost, // Max gas deducted from user's L2 balance to cover base submission fee. Usually 0
                bytes(""), // bytes extraData hook
                gasCost // Total gas deducted from user’s L2 balance
            )
        );
    }

    /* ============ Privileged Functions ============ */

    /**
     * @dev Whitelist the assets that can be deposited
     * @param _assets array of addresses of the assets to be whitelisted
     */
    function whitelistAssets(address[] calldata _assets, bool[] calldata _flags) external override onlyOwner {
        if (_assets.length != _flags.length) revert InvalidAssets();
        for (uint256 i = 0; i < _assets.length; i++) {
            allowedAssets[_assets[i]] = _flags[i];
        }
    }

    /**
     * @dev Whitelist the final assets that can be deposited
     * @param _assets array of addresses of the assets to be whitelisted
     */
    function whitelistFinalAssets(address[] calldata _assets, bool[] calldata _flags) external override onlyOwner {
        if (_assets.length != _flags.length) revert InvalidAssets();
        for (uint256 i = 0; i < _assets.length; i++) {
            finalAllowedAssets[_assets[i]] = _flags[i];
        }
    }

    /* ============ Private Functions ============ */

    function _swap(
        address kintoWallet,
        address inputAsset,
        address finalAsset,
        uint256 amount,
        uint256 minReceive,
        bytes calldata swapCallData
    ) private returns (uint256 amountBought) {
        amountBought = amount;
        if (inputAsset != finalAsset) {
            return amount;
        }

        if (inputAsset == ETH && finalAsset == wstETH) {
            return _stakeEthToWstEth(amount);
        }

        if (inputAsset == ETH) {
            WETH.deposit{value: amount}();
            inputAsset = address(WETH);
        }

        if (finalAsset != inputAsset) {
            amountBought = _fillQuote(
                amount,
                IERC20(inputAsset),
                // if sUSDE, swap to USDe & then stake
                IERC20(finalAsset == sUSDe ? USDe : finalAsset),
                swapCallData,
                minReceive
            );
        }

        if (finalAsset == sUSDe) {
            amountBought = _stakeUSDe(USDe, amountBought);
        }
    }

    function _stakeEthToWstEth(uint256 amount) private returns (uint256 amountBought) {
        // Shortcut to stake ETH and auto-wrap returned stETH
        uint256 balanceBefore = ERC20(wstETH).balanceOf(address(this));
        (bool sent,) = wstETH.call{value: amount}("");
        if (!sent) revert InvalidAmount(amount);
        amountBought = ERC20(wstETH).balanceOf(address(this)) - balanceBefore;
    }

    function _stakeUSDe(address asset, uint256 amount) private returns (uint256) {
        IERC20(asset).safeApprove(address(sUSDe), amount);
        return IsUSDe(sUSDe).deposit(amount, address(this));
    }

    /**
     * @dev Permit the spender to spend the specified amount of tokens on behalf of the owner
     * @param owner sender of the tokens
     * @param asset address of the token
     * @param amount amount of tokens
     * @param expiresAt deadline for the signature
     * @param nonce (only for DAI permit), nonce of the last permit transaction of a user’s wallet
     * @param signature signature to be recovered
     */
    function _permit(
        address owner,
        address asset,
        uint256 amount,
        uint256 expiresAt,
        uint256 nonce,
        bytes calldata signature
    ) private {
        if (IERC20(asset).allowance(owner, address(this)) >= amount) {
            // If allowance is already set, we don't need to call permit
            return;
        }

        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := calldataload(add(signature.offset, 0x00))
            s := calldataload(add(signature.offset, 0x20))
        }

        v = uint8(signature[64]); // last byte

        if (asset == DAI) {
            // DAI uses a different permit function, only infinite allowance is supported
            IDAI(asset).permit(owner, address(this), nonce, expiresAt, true, v, r, s);
            return;
        }
        ERC20Permit(asset).permit(owner, address(this), amount, expiresAt, v, r, s);
    }

    /**
     * @dev Swaps ERC20->ERC20 tokens held by this contract using a 0x-API quote.
     */
    function _fillQuote(
        uint256 amountIn,
        // The `sellTokenAddress` field from the API response.
        IERC20 sellToken,
        // The `buyTokenAddress` field from the API response.
        IERC20 buyToken,
        // The `data` field from the API response.
        bytes calldata swapCallData,
        // Slippage protection
        uint256 minReceive
    ) private returns (uint256) {
        // Increase the allowance for the exchangeProxy to handle `amountIn` of `sellToken`
        sellToken.safeIncreaseAllowance(exchangeProxy, amountIn);

        // Track our balance of the buyToken to determine how much we've bought.
        uint256 boughtAmount = buyToken.balanceOf(address(this));

        // Perform the swap call to the exchange proxy.
        exchangeProxy.functionCall(swapCallData);
        // Keep the protocol fee refunds given that we are paying for gas
        // Use our current buyToken balance to determine how much we've bought.
        boughtAmount = buyToken.balanceOf(address(this)) - boughtAmount;

        if (boughtAmount < minReceive) revert SlippageError(boughtAmount, minReceive);

        return boughtAmount;
    }

    function _checkFinalAsset(address finalAsset) internal {
        if (!finalAllowedAssets[finalAsset]) {
            revert InvalidFinalAsset(finalAsset);
        }
    }

    /* ============ Signature Recovery ============ */

    /**
     * @dev Check that the signature is valid and it has not used yet
     * @param _signature signature to be recovered.
     */
    modifier onlySignerVerified(IBridger.SignatureData calldata _signature) {
        if (block.timestamp > _signature.expiresAt) revert SignatureExpired();
        if (nonces[_signature.signer] != _signature.nonce) revert InvalidNonce();

        bytes32 digest = MessageHashUtils.toTypedDataHash(domainSeparator, _hashSignatureData(_signature));
        if (!_signature.signer.isValidSignatureNow(digest, _signature.signature)) revert InvalidSigner();
        _;
    }

    /* ============ EIP-712 Helpers ============ */

    function _domainSeparatorV4() internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("Bridger")), // this contract's name
                keccak256(bytes("1")), // version
                block.chainid,
                address(this)
            )
        );
    }

    function _hashSignatureData(SignatureData calldata depositData) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                keccak256(
                    "SignatureData(address kintoWallet,address signer,address inputAsset,uint256 amount,uint256 minReceive,address finalAsset,uint256 nonce,uint256 expiresAt)"
                ),
                depositData.kintoWallet,
                depositData.signer,
                depositData.inputAsset,
                depositData.amount,
                depositData.minReceive,
                depositData.finalAsset,
                depositData.nonce,
                depositData.expiresAt
            )
        );
    }

    /* ============ Fallback ============ */

    receive() external payable {}
}
