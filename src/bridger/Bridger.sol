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

import "@kinto-core/interfaces/bridger/IBridger.sol";
import "@kinto-core/interfaces/bridger/IBridge.sol";

import "forge-std/console2.sol";

/**
 * @title Bridger
 * @notice Users can bridge tokens in to the Kinto L2 using this contract.
 * The contract will swap the tokens if needed and deposit them in to the Kinto L2
 * Users can select one of `finalAllowedAssets` assets to bridge in to the Kinto L2
 * Input assets are restricted by `allowedAssets`.
 * Users can deposit by signature, providing ERC20 tokens or pure ETH.
 * If depositing ETH and final asset is wstETH, it is just converted to wstETH (no swap is done).
 * If depositing ETH and final asset is other than wstETH, ETH is first wrapped to WETH and then swapped to desired asset.
 * If USDe is provided, it is directly staked to sUSDe.
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
    address public constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    IWETH public immutable WETH;
    address public immutable DAI;
    address public immutable USDe;
    address public immutable sUSDe;
    address public immutable wstETH;

    bytes32 public immutable override domainSeparator;
    address public immutable override l2Vault;
    /// @notice The address of the 0x exchange proxy through which swaps are executed.
    address public immutable swapRouter;

    /* ============ State Variables ============ */
    address public override senderAccount;

    /// @dev Mapping of input assets that are allowed
    mapping(address => bool) public override allowedAssets;
    /// @dev DEPRECATED
    mapping(address => mapping(address => uint256)) private deposits;
    /// @dev We include a nonce in every hashed message, and increment the nonce as part of a
    /// state-changing operation, so as to prevent replay attacks, i.e. the reuse of a signature.
    mapping(address => uint256) public override nonces;
    /// @dev Count of deposits
    uint256 public depositCount;
    /// @dev DEPRECATED
    bool private swapsEnabled;
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
     * @param exchange The address of the exchange proxy to be used for token swaps.
     */
    constructor(
        address vault,
        address exchange,
        address weth,
        address dai,
        address usde,
        address sUsde,
        address wstEth
    ) {
        _disableInitializers();

        domainSeparator = _domainSeparatorV4();
        l2Vault = vault;
        swapRouter = exchange;

        WETH = IWETH(weth);
        DAI = dai;
        USDe = usde;
        sUSDe = sUsde;
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
     * @param permitSig Signature to be recovered to allow the spender to spend the tokens
     */
    function depositBySig(
        bytes calldata permitSig,
        IBridger.SignatureData calldata depositData,
        bytes calldata swapCallData,
        BridgeData calldata bridgeData
    ) external payable override whenNotPaused nonReentrant onlyPrivileged onlySignerVerified(depositData) {
        _permit(
            depositData.signer,
            depositData.inputAsset,
            depositData.amount,
            depositData.expiresAt,
            ERC20Permit(depositData.inputAsset).nonces(depositData.signer),
            permitSig
        );

        _deposit(
            depositData.signer,
            depositData.inputAsset,
            depositData.amount,
            depositData.kintoWallet,
            depositData.finalAsset,
            depositData.minReceive,
            swapCallData,
            bridgeData
        );
    }

    function depositERC20(
        address inputAsset,
        uint256 amount,
        address kintoWallet,
        address finalAsset,
        uint256 minReceive,
        bytes calldata swapCallData,
        BridgeData calldata bridgeData
    ) external payable override whenNotPaused nonReentrant {
        _deposit(msg.sender, inputAsset, amount, kintoWallet, finalAsset, minReceive, swapCallData, bridgeData);
    }

    /**
     * @dev Deposit the specified amount of ETH in to the Kinto L2 as finalAsset
     * @param kintoWallet Kinto Wallet Address on L2 where tokens will be deposited
     * @param finalAsset Asset to depositInto
     * @param swapCallData Struct with all the required information to swap the tokens
     */
    function depositETH(
        uint256 amount,
        address kintoWallet,
        address finalAsset,
        uint256 minReceive,
        bytes calldata swapCallData,
        BridgeData calldata bridgeData
    ) external payable override whenNotPaused nonReentrant {
        _checkFinalAsset(finalAsset);

        if (amount == 0) revert InvalidAmount(amount);

        uint256 amountBought = _swap(ETH, finalAsset, amount, minReceive, swapCallData);

        // Bridge the final amount to Kinto
        IERC20(finalAsset).safeIncreaseAllowance(bridgeData.vault, amountBought);
        IBridge(bridgeData.vault).bridge{value: bridgeData.gasFee}(
            kintoWallet,
            amountBought,
            bridgeData.msgGasLimit,
            bridgeData.connector,
            bridgeData.execPayload,
            bridgeData.options
        );

        emit Bridged(msg.sender, kintoWallet, ETH, amount, finalAsset, amountBought);
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

    function _deposit(
        address user,
        address inputAsset,
        uint256 amount,
        address kintoWallet,
        address finalAsset,
        uint256 minReceive,
        bytes calldata swapCallData,
        BridgeData calldata bridgeData
    ) internal {
        if (amount == 0) revert InvalidAmount(0);

        _checkFinalAsset(finalAsset);

        if (inputAsset != finalAsset && !allowedAssets[inputAsset]) {
            revert InvalidInputAsset(inputAsset);
        }

        // slither-disable-next-line arbitrary-send-erc20
        IERC20(inputAsset).safeTransferFrom(user, address(this), amount);

        uint256 amountBought = _swap(inputAsset, finalAsset, amount, minReceive, swapCallData);

        // Bridge the final amount to Kinto
        IERC20(finalAsset).safeIncreaseAllowance(bridgeData.vault, amountBought);
        IBridge(bridgeData.vault).bridge{value: bridgeData.gasFee}(
            kintoWallet,
            amountBought,
            bridgeData.msgGasLimit,
            bridgeData.connector,
            bridgeData.execPayload,
            bridgeData.options
        );

        emit Bridged(user, kintoWallet, inputAsset, amount, finalAsset, amountBought);
    }

    function _swap(
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
                // if sUSDe, swap to USDe & then stake
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
        if (!sent) revert FailedToStakeEth();
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
        // Increase the allowance for the swapRouter to handle `amountIn` of `sellToken`
        sellToken.safeIncreaseAllowance(swapRouter, amountIn);

        // Track our balance of the buyToken to determine how much we've bought.
        uint256 boughtAmount = buyToken.balanceOf(address(this));

        // Perform the swap call to the exchange proxy.
        swapRouter.functionCall(swapCallData);
        // Keep the protocol fee refunds given that we are paying for gas
        // Use our current buyToken balance to determine how much we've bought.
        boughtAmount = buyToken.balanceOf(address(this)) - boughtAmount;

        if (boughtAmount < minReceive) revert SlippageError(boughtAmount, minReceive);

        return boughtAmount;
    }

    function _checkFinalAsset(address finalAsset) internal view {
        if (!finalAllowedAssets[finalAsset]) {
            revert InvalidFinalAsset(finalAsset);
        }
    }

    /* ============ Signature Recovery ============ */

    /**
     * @dev Check that the signature is valid and it has not used yet
     * @param args Signature data.
     */
    modifier onlySignerVerified(IBridger.SignatureData calldata args) {
        if (block.timestamp > args.expiresAt) revert SignatureExpired();
        if (nonces[args.signer] != args.nonce) revert InvalidNonce();

        bytes32 digest = MessageHashUtils.toTypedDataHash(domainSeparator, _hashSignatureData(args));
        if (!args.signer.isValidSignatureNow(digest, args.signature)) revert InvalidSigner();

        nonces[args.signer]++;
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
