// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../interfaces/IBridger.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@oz/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@oz/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@oz/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@oz/contracts/utils/cryptography/MessageHashUtils.sol";
import {SignatureChecker} from "@oz/contracts/utils/cryptography/SignatureChecker.sol";

// todo
contract L1GatewayRouter {}

/**
 * @title Bridger - To be deployed on ETH mainnet and on Kinto L2
 *
 */
contract Bridger is Initializable, UUPSUpgradeable, OwnableUpgradeable, IBridger {
    using MessageHashUtils for bytes32;
    using SignatureChecker for address;

    /* ============ Events ============ */
    event Deposit(address indexed from, address indexed asset, uint256 amount, address indexed assetBought, uint256 amountBought);

    /* ============ Constants ============ */
    address public constant REFUND_L2_ACCOUNT = address(1);
    address public constant SENDER_ACCOUNT = address(1);

    /* ============ State Variables ============ */
    address public immutable override arbitrumL1GatewayRouter;
    /// @dev Mapping of all depositors by user address and asset address
    mapping(address => mapping(address => uint256)) public override deposits;
    /// @dev We include a nonce in every hashed message, and increment the nonce as part of a
    /// state-changing operation, so as to prevent replay attacks, i.e. the reuse of a signature.
    mapping(address => uint256) public override nonces;
    /// @dev Count of deposits
    uint256 public depositCount;

    /* ============ Constructor & Upgrades ============ */
    constructor(address _arbitrumL1GatewayRouter) {
        _disableInitializers();
        arbitrumL1GatewayRouter = _arbitrumL1GatewayRouter; // 0xD9041DeCaDcBA88844b373e7053B4AC7A3390D60
    }

    /**
     * @dev Upgrade calling `upgradeTo()`
     */
    function initialize() external initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
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
    ) external override onlySignerVerified(_signatureData) {
        if (msg.sender != owner() && msg.sender != SENDER_ACCOUNT) {
            revert OnlySender();
        }
        _permit(_signatureData.inputAsset, _signatureData.amount, _signatureData.expiresAt, _permitSignature);
        // Lock deposit in this contract
        _deposit(_signatureData.inputAsset, amountBought);
        // swap using 0x
        uint256 amountBought = _fillQuote(
            IERC20(_signatureData.inputAsset),
            IERC20(_signatureData.finalAsset),
            payable(_swapData.spender),
            payable(_swapData.swapTarget),
            _swapData.swapCallData
        );
        nonces[_signatureData.signer]++;
        // Bridge to Kinto L2 using arbitrum or superbridge
        // L1GatewayRouter(arbitrumL1GatewayRouter).outboundTransferCustomRefund(
        //     _signatureData.finalAsset, //token
        //     REFUND_L2_ACCOUNT, // Account to be credited with the excess gas refund in L2
        //     _kintoWallet, // Account to be credited with the tokens in L2
        //     amountBought, // Amount of tokens to bridge
        //     _swapData.maxGas, // Max gas deducted from user’s L2 balance to cover the execution in L2
        //     _swapData.gasPriceBid, // Gas price for the execution in L2
        //     abi.encode(0, bytes("")) // 2 pieces of data encoded: uint256 maxSubmissionCost, bytes extraData
        // );
        depositCount++;
        emit Deposit(msg.sender, _signatureData.inputAsset, _signatureData.amount, _signatureData.finalAsset, amountBought);
    }

    /* ============ Private methods ============ */

    /**
     * @dev Permit the spender to spend the specified amount of tokens on behalf of the owner
     * @param asset address of the token
     * @param amount amount of tokens
     * @param expiresAt deadline for the signature
     * @param signature signature to be recovered
     */
    function _permit(address asset, uint256 amount, uint256 expiresAt, bytes memory signature) private {
        // fix Index range access is only supported for dynamic calldata arrays.
        (uint8 v, bytes32 r, bytes32 s) = abi.decode(signature, (uint8, bytes32, bytes32));
        ERC20Permit(asset).permit(msg.sender, address(this), amount, expiresAt, v, r, s);
    }

    /**
     * @dev Deposit the specified amount of tokens
     * @param asset address of the token
     * @param amount amount of tokens
     */
    function _deposit(address asset, uint256 amount) private {
        require(amount > 0, "Bridger: amount must be greater than 0");
        require(IERC20(asset).balanceOf(msg.sender) >= amount, "Bridger: insufficient balance");
        require(IERC20(asset).allowance(msg.sender, address(this)) >= amount, "Bridger: insufficient allowance");
        IERC20(asset).transferFrom(msg.sender, address(this), amount);
        deposits[msg.sender][asset] += amount;
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
        // Note that for some tokens (e.g., USDT, KNC), you must first reset any existing
        // allowance to 0 before being able to update it.
        require(sellToken.approve(spender, type(uint256).max), "Failed to approve spender");
        // Call the encoded swap function call on the contract at `swapTarget`,
        // passing along any ETH attached to this function call to cover protocol fees.
        (bool success,) = swapTarget.call{value: msg.value}(swapCallData);
        require(success, "SWAP_CALL_FAILED");
        // Keep the protocol fee redunds
        // msg.sender.transfer(address(this).balance);

        // Use our current buyToken balance to determine how much we've bought.
        boughtAmount = buyToken.balanceOf(address(this)) - boughtAmount;
        return boughtAmount;
    }

    receive() external payable {}

    /* ============ Signature Recovery ============ */

    /**
     * @dev Check that the signature is valid and it has not used yet
     * @param _signature signature to be recovered.
     */
    modifier onlySignerVerified(IBridger.SignatureData calldata _signature) {
        if (block.timestamp >= _signature.expiresAt) revert SignatureExpired();
        if (nonces[_signature.signer] != _signature.nonce) revert InvalidNonce();

        bytes32 dataHash = keccak256(
            abi.encode(
                _signature.signer,
                address(this),
                _signature.inputAsset,
                _signature.amount,
                _signature.expiresAt,
                nonces[_signature.signer],
                block.chainid
            )
        ).toEthSignedMessageHash(); // EIP-712 hash

        if (!_signature.signer.isValidSignatureNow(dataHash, _signature.signature)) revert InvalidSigner();
        _;
    }
}
