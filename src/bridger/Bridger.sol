// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../interfaces/IBridger.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
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
    event BoughtTokens(IERC20 sellToken, IERC20 buyToken, uint256 boughtAmount);
    event Deposit(address indexed from, address indexed asset, uint256 amount);

    /* ============ Constants ============ */
    address public constant REFUND_L2_ACCOUNT = address(1);
    address public constant SENDER_ACCOUNT = address(1);

    /* ============ State Variables ============ */
    address public immutable override arbitrumL1GatewayRouter;
    mapping(address => mapping(address => uint256)) public override deposits;
    /// @dev We include a nonce in every hashed message, and increment the nonce as part of a
    /// state-changing operation, so as to prevent replay attacks, i.e. the reuse of a signature.
    mapping(address => uint256) public override nonces;

    /* ============ Constructor & Upgrades ============ */
    constructor(address _arbitrumL1GatewayRouter) {
        _disableInitializers();
        arbitrumL1GatewayRouter = _arbitrumL1GatewayRouter;
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
     * @param _signatureData Struct with all the required information to deposit via signature
     */
    function depositBySig(IBridger.SignatureData calldata _signatureData)
        external
        override
        onlySignerVerified(_signatureData)
    {
        require(msg.sender == owner() || msg.sender == SENDER_ACCOUNT, "Bridger: unauthorized sender");
        _permit(_signatureData.asset, _signatureData.amount, _signatureData.expiresAt, _signatureData.permitSignature);
        // swap using 0x
        uint256 amountBought = _fillQuote(
            IERC20(_signatureData.depositAsset),
            IERC20(_signatureData.asset),
            payable(_signatureData.spender),
            payable(_signatureData.swapTarget),
            _signatureData.swapCallData
        );
        // Lock deposit in this contract
        _deposit(_signatureData.asset, amountBought);
        nonces[_signatureData.signer]++;
        // Bridge to Kinto L2 using arbitrum or superbridge
        // L1GatewayRouter(arbitrumL1GatewayRouter).outboundTransferCustomRefund(
        //     _signatureData.asset, //token
        //     REFUND_L2_ACCOUNT, // Account to be credited with the excess gas refund in L2
        //     _signatureData.signerKintoWallet, // Account to be credited with the tokens in L2
        //     amountBought, // Amount of tokens to bridge
        //     _signatureData.maxGas, // Max gas deducted from user’s L2 balance to cover the execution in L2
        //     _signatureData.gasPriceBid, // Gas price for the execution in L2
        //     abi.encode(0, bytes("")) // 2 pieces of data encoded: uint256 maxSubmissionCost, bytes extraData
        // );
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
        IERC20(asset).permit(
            msg.sender, address(this), amount, expiresAt, signature[64], signature[0:32], signature[32:64]
        );
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
        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
        deposits[msg.sender][asset] += amount;
        emit Deposit(msg.sender, asset, amount);
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
        require(sellToken.approve(spender, uint256(-1)));
        // Call the encoded swap function call on the contract at `swapTarget`,
        // passing along any ETH attached to this function call to cover protocol fees.
        (bool success,) = swapTarget.call{value: msg.value}(swapCallData);
        require(success, "SWAP_CALL_FAILED");
        // Keep the protocol fee redunds
        // msg.sender.transfer(address(this).balance);

        // Use our current buyToken balance to determine how much we've bought.
        boughtAmount = buyToken.balanceOf(address(this)) - boughtAmount;
        emit BoughtTokens(sellToken, buyToken, boughtAmount);
        return boughtAmount;
    }

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
                _signature.depositAsset,
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
