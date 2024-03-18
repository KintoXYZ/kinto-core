// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../interfaces/IBridger.sol";
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
    using SignatureChecker for address;
    using ECDSA for bytes32;
    using SafeERC20 for IERC20;

    /* ============ Events ============ */
    event Deposit(
        address indexed from,
        address indexed wallet,
        address indexed asset,
        uint256 amount,
        address assetBought,
        uint256 amountBought,
        uint256 depositCount
    );

    /* ============ Constants ============ */
    address public constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    IWETH public constant WETH = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public constant sDAI = 0x83F20F44975D03b1b09e64809B757c47f942BEeA;
    address public constant USDe = 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3;
    address public constant sUSDe = 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497;
    address public constant wstETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address public constant weETH = 0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee;

    IL1GatewayRouter public constant L1GatewayRouter = IL1GatewayRouter(0xD9041DeCaDcBA88844b373e7053B4AC7A3390D60);
    address public constant standardGateway = 0x7870D5398DB488c669B406fBE57b8d05b6A35e42;

    /* ============ State Variables ============ */
    bytes32 public immutable override domainSeparator;
    address public immutable override l2Vault;
    address public immutable exchangeProxy;
    address public override senderAccount;

    /// @dev Mapping of input assets that are allowed
    mapping(address => bool) public override allowedAssets;
    /// @dev Mapping of all depositors by user address and asset address
    mapping(address => mapping(address => uint256)) public override deposits;
    /// @dev We include a nonce in every hashed message, and increment the nonce as part of a
    /// state-changing operation, so as to prevent replay attacks, i.e. the reuse of a signature.
    mapping(address => uint256) public override nonces;
    /// @dev Count of deposits
    uint256 public depositCount;
    /// @dev Enable or disable swaps
    bool public swapsEnabled;

    /* ============ Modifiers ============ */
    modifier onlyPrivileged() {
        if (msg.sender != owner() && msg.sender != senderAccount) revert OnlyOwner();
        _;
    }

    /* ============ Constructor & Upgrades ============ */
    constructor(address _l2Vault) {
        _disableInitializers();
        domainSeparator = _domainSeparatorV4();
        l2Vault = _l2Vault;
        exchangeProxy = 0xDef1C0ded9bec7F1a1670819833240f027b25EfF;
    }

    /**
     * @dev Upgrade calling `upgradeTo()`
     */
    function initialize(address _senderAccount) external initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();
        __Pausable_init();

        _transferOwnership(msg.sender);
        swapsEnabled = false;
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

    /* ============ Deposit methods ============ */

    /**
     * @dev Deposit the specified amount of tokens in to the Kinto L2
     * @param _signatureData Struct with all the required information to deposit via signature
     * @param _permitSignature Signature to be recovered to allow the spender to spend the tokens
     */
    function depositBySig(
        bytes calldata _permitSignature,
        IBridger.SignatureData calldata _signatureData,
        IBridger.SwapData calldata _swapData
    ) external payable override whenNotPaused nonReentrant onlyPrivileged onlySignerVerified(_signatureData) {
        _isFinalAssetAllowed(_signatureData.finalAsset);
        if (_signatureData.inputAsset != _signatureData.finalAsset && !allowedAssets[_signatureData.inputAsset]) {
            // checks for USDe special case
            if (_signatureData.inputAsset != USDe || _signatureData.finalAsset != sUSDe) {
                revert InvalidAsset();
            }
        }

        nonces[_signatureData.signer]++;
        _permit(
            _signatureData.signer,
            _signatureData.inputAsset,
            _signatureData.amount,
            _signatureData.expiresAt,
            ERC20Permit(_signatureData.inputAsset).nonces(_signatureData.signer),
            _permitSignature
        );
        _deposit(_signatureData.signer, _signatureData.inputAsset, _signatureData.amount);
        _swap(
            _signatureData.signer,
            _signatureData.kintoWallet,
            _signatureData.inputAsset,
            _signatureData.finalAsset,
            _signatureData.amount,
            _signatureData.minReceive,
            _swapData
        );
    }

    /**
     * @dev Deposit the specified amount of ETH in to the Kinto L2 as finalAsset
     * @param _kintoWallet Kinto Wallet Address on L2 where tokens will be deposited
     * @param _finalAsset Asset to depositInto
     * @param _swapData Struct with all the required information to swap the tokens
     */
    function depositETH(
        address _kintoWallet,
        address _finalAsset,
        uint256 _minReceive,
        IBridger.SwapData calldata _swapData
    ) external payable override whenNotPaused nonReentrant {
        _isFinalAssetAllowed(_finalAsset);
        if (msg.value < 0.1 ether) revert InvalidAmount();
        deposits[msg.sender][ETH] += msg.value - _swapData.gasFee;
        _swap(msg.sender, _kintoWallet, ETH, _finalAsset, msg.value, _minReceive, _swapData);
    }

    /**
     * @dev Bridges deposits in bulk every hour to the L2
     */
    function bridgeDeposits(address asset, uint256 maxGas, uint256 gasPriceBid, uint256 maxSubmissionCost)
        external
        payable
        override
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

    /* ============ Privileged Admin methods ============ */

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
     * @dev Enable or disable swaps
     * @param _swapsEnabled bool to enable or disable swaps
     */
    function setSwapsEnabled(bool _swapsEnabled) external override onlyOwner {
        swapsEnabled = _swapsEnabled;
    }

    /* ============ Private methods ============ */

    function _swap(
        address _sender,
        address _kintoWallet,
        address _inputAsset,
        address _finalAsset,
        uint256 _amount,
        uint256 _minReceive,
        SwapData calldata _swapData
    ) private {
        uint256 amountBought = _amount;
        if (_inputAsset != _finalAsset) {
            if (_inputAsset == ETH && _finalAsset == wstETH) {
                amountBought = _swapETHtoWstETH(_amount);
            } else {
                if (_inputAsset == ETH) {
                    _amount = _amount - _swapData.gasFee;
                    WETH.deposit{value: _amount}();
                    _inputAsset = address(WETH);
                }
                amountBought = _executeSwap(_inputAsset, _finalAsset, _amount, _minReceive, _swapData);
            }

            if (_finalAsset == sUSDe) {
                amountBought = _stakeAssets(USDe, amountBought);
            }
        }

        depositCount++;
        emit Deposit(_sender, _kintoWallet, _inputAsset, _amount, _finalAsset, amountBought, depositCount);
    }

    function _executeSwap(
        address _inputAsset,
        address _finalAsset,
        uint256 _amount,
        uint256 _minReceive,
        SwapData calldata _swapData
    ) private returns (uint256 amountBought) {
        amountBought = _amount;
        if (_finalAsset == sUSDe) _finalAsset = USDe; // if sUSDE, swap to USDe & then stake
        if (_finalAsset != _inputAsset) {
            if (!swapsEnabled) revert SwapsDisabled();
            amountBought = _fillQuote(
                _amount,
                _swapData.gasFee,
                IERC20(_inputAsset),
                IERC20(_finalAsset),
                payable(_swapData.spender),
                payable(_swapData.swapTarget),
                _swapData.swapCallData,
                _minReceive
            );
        }
    }

    function _swapETHtoWstETH(uint256 _amount) private returns (uint256 amountBought) {
        // Shortcut to stake ETH and auto-wrap returned stETH
        uint256 balanceBefore = ERC20(wstETH).balanceOf(address(this));
        (bool sent,) = wstETH.call{value: _amount}("");
        if (!sent) revert InvalidAmount();
        amountBought = ERC20(wstETH).balanceOf(address(this)) - balanceBefore;
    }

    function _stakeAssets(address _asset, uint256 _amount) private returns (uint256) {
        IERC20(_asset).safeApprove(address(sUSDe), _amount);
        return IsUSDe(sUSDe).deposit(_amount, address(this));
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
        IERC20(asset).safeTransferFrom(sender, address(this), amount);
        deposits[sender][asset] += amount;
    }

    /**
     * @dev Swaps ERC20->ERC20 tokens held by this contract using a 0x-API quote.
     */
    function _fillQuote(
        uint256 amount,
        uint256 gasFee,
        // The `sellTokenAddress` field from the API response.
        IERC20 sellToken,
        // The `buyTokenAddress` field from the API response.
        IERC20 buyToken,
        // The `allowanceTarget` field from the API response.
        address spender,
        // The `to` field from the API response.
        address payable swapTarget,
        // The `data` field from the API response.
        bytes calldata swapCallData,
        // Slippage protection
        uint256 minReceive
    ) private returns (uint256) {
        // Checks that the swapTarget is actually the address of 0x ExchangeProxy
        if (swapTarget != exchangeProxy) revert OnlyExchangeProxy();
        if (gasFee >= 0.05 ether) revert GasFeeTooHigh();

        // Track our balance of the buyToken to determine how much we've bought.
        uint256 boughtAmount = buyToken.balanceOf(address(this));

        // Give `spender` an allowance to spend this tx's `sellToken`.
        sellToken.safeApprove(spender, amount);
        // Call the encoded swap function call on the contract at `swapTarget`,
        // passing along any ETH attached to this function call to cover protocol fees.
        (bool success,) = swapTarget.call{value: gasFee}(swapCallData);
        if (!success) revert SwapCallFailed();
        // Keep the protocol fee refunds given that we are paying for gas
        // Use our current buyToken balance to determine how much we've bought.
        boughtAmount = buyToken.balanceOf(address(this)) - boughtAmount;
        if (boughtAmount < minReceive) revert SlippageError();
        return boughtAmount;
    }

    receive() external payable {}

    function _isFinalAssetAllowed(address _asset) private pure {
        if (
            _asset != address(sDAI) && _asset != address(sUSDe) && _asset != address(wstETH) && _asset != address(weETH)
        ) revert InvalidAsset();
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

    function _hashSignatureData(SignatureData calldata signatureData) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                keccak256(
                    "SignatureData(address kintoWallet,address signer,address inputAsset,uint256 amount,uint256 minReceive,address finalAsset,uint256 nonce,uint256 expiresAt)"
                ),
                signatureData.kintoWallet,
                signatureData.signer,
                signatureData.inputAsset,
                signatureData.amount,
                signatureData.minReceive,
                signatureData.finalAsset,
                signatureData.nonce,
                signatureData.expiresAt
            )
        );
    }
}

contract BridgerV3 is Bridger {
    constructor(address _l2Vault) Bridger(_l2Vault) {}
}
