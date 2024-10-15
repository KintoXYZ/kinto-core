// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {IFaucet} from "./interfaces/IFaucet.sol";
import {IKintoWalletFactory} from "./interfaces/IKintoWalletFactory.sol";
import {IKintoID} from "./interfaces/IKintoID.sol";

/**
 * @title Faucet
 * @dev The Kinto Faucet gives a bit of ETH to users to pay for gas fees
 */
contract Faucet is Initializable, UUPSUpgradeable, OwnableUpgradeable, IFaucet {
    using ECDSA for bytes32;
    using SignatureChecker for address;

    /* ============ Events ============ */

    event Claim(address indexed _to, uint256 _timestamp);

    /* ============ Constants ============ */

    uint256 public constant CLAIM_AMOUNT = 1 ether / 2000;
    uint256 public constant FAUCET_AMOUNT = 1 ether;

    /* ============ State Variables ============ */

    IKintoWalletFactory public immutable override walletFactory;
    mapping(address => bool) public override claimed;
    bool public active;

    /// @dev We include a nonce in every hashed message, and increment the nonce as part of a
    /// state-changing operation, so as to prevent replay attacks, i.e. the reuse of a signature.
    mapping(address => uint256) public override nonces;

    IKintoID public immutable kintoID;

    /* ============ Constructor & Upgrades ============ */
    constructor(address _kintoWalletFactory) {
        _disableInitializers();
        walletFactory = IKintoWalletFactory(_kintoWalletFactory);
        kintoID = IKintoID(walletFactory.kintoID());
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

    /* ============ Claim methods ============ */

    /**
     * @dev Allows users to claim KintoETH from the smart contract's faucet once per account
     */
    function claimKintoETH() external override {
        _privateClaim(msg.sender);
    }

    /**
     * @dev Claim via meta tx on behalf of a new account by the owner
     * @param _signatureData Signature data
     */
    function claimKintoETH(IFaucet.SignatureData calldata _signatureData) external onlySignerVerified(_signatureData) {
        if (msg.sender != address(walletFactory)) revert OnlyFactory();
        kintoID.isKYC(_signatureData.signer);
        _privateClaim(_signatureData.signer);
        nonces[_signatureData.signer]++;
    }

    /**
     * @dev Claim via Kinto ID when it is minting
     * @param _receiver Address of the receiver
     */
    function claimOnCreation(address _receiver) external {
        if (msg.sender != address(kintoID)) revert OnlyKintoID();
        _privateClaim(_receiver);
    }

    /**
     * @dev Function to withdraw all eth by owner
     */
    function withdrawAll() external override onlyOwner {
        payable(msg.sender).transfer(address(this).balance);
        active = false;
    }

    /**
     * @dev Function to start the faucet
     */
    function startFaucet() external payable override onlyOwner {
        if (address(this).balance < FAUCET_AMOUNT) revert NotEnoughETH();
        active = true;
    }

    /**
     * @dev Allows the contract to receive Ether
     */
    receive() external payable {}

    /* ============ Private functions ============ */

    function _privateClaim(address _receiver) private {
        if (!active) revert FaucetNotActive();
        if (claimed[_receiver]) revert AlreadyClaimed();
        claimed[_receiver] = true;
        payable(_receiver).transfer(CLAIM_AMOUNT);
        if (address(this).balance < CLAIM_AMOUNT) {
            active = false;
        }
        emit Claim(_receiver, block.timestamp);
    }

    /* ============ Signature Recovery ============ */

    /**
     * @dev Check that the signature is valid and the address has not claimed yet.
     * @param _signature signature to be recovered.
     */
    modifier onlySignerVerified(IFaucet.SignatureData calldata _signature) {
        if (block.timestamp >= _signature.expiresAt) revert SignatureExpired();
        if (nonces[_signature.signer] != _signature.nonce) revert InvalidNonce();

        bytes32 dataHash = keccak256(
            abi.encode(_signature.signer, address(this), _signature.expiresAt, nonces[_signature.signer], block.chainid)
        ).toEthSignedMessageHash(); // EIP-712 hash

        if (!_signature.signer.isValidSignatureNow(dataHash, _signature.signature)) revert InvalidSigner();
        _;
    }
}

contract FaucetV9 is Faucet {
    constructor(address _kintoWalletFactory) Faucet(_kintoWalletFactory) {}
}
