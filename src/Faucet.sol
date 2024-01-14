// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {IFaucet} from "./interfaces/IFaucet.sol";
import {IKintoWalletFactory} from "./interfaces/IKintoWalletFactory.sol";

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
    uint256 public constant CLAIM_AMOUNT = 1 ether / 3000;
    uint256 public constant FAUCET_AMOUNT = 1 ether;

    /* ============ State Variables ============ */

    IKintoWalletFactory public immutable override walletFactory;
    mapping(address => bool) public override claimed;
    bool public active;

    /// @dev We include a nonce in every hashed message, and increment the nonce as part of a
    /// state-changing operation, so as to prevent replay attacks, i.e. the reuse of a signature.
    mapping(address => uint256) public override nonces;

    /* ============ Constructor & Upgrades ============ */
    constructor(address _kintoWalletFactory) {
        _disableInitializers();
        walletFactory = IKintoWalletFactory(_kintoWalletFactory);
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
        require(msg.sender == owner(), "only owner");
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
    function claimOnBehalf(IFaucet.SignatureData calldata _signatureData) external onlySignerVerified(_signatureData) {
        require(msg.sender == address(walletFactory), "Only wallet factory can call this");
        _privateClaim(_signatureData.signer);
        nonces[_signatureData.signer]++;
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
        require(msg.value >= FAUCET_AMOUNT, "Not enough ETH to start faucet");
        active = true;
    }

    /**
     * @dev Allows the contract to receive Ether
     */
    receive() external payable {}

    /* ============ Private functions ============ */

    function _privateClaim(address _receiver) private {
        require(active, "Faucet is not active");
        require(!claimed[_receiver], "You have already claimed your KintoETH");
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
        require(block.timestamp < _signature.expiresAt, "Signature has expired");
        require(nonces[_signature.signer] == _signature.nonce, "Invalid Nonce");
        bytes32 hash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                keccak256(
                    abi.encode(
                        _signature.signer,
                        address(this),
                        _signature.expiresAt,
                        nonces[_signature.signer],
                        bytes32(block.chainid)
                    )
                )
            )
        ) // EIP-191 header
            .toEthSignedMessageHash();

        require(_signature.signer.isValidSignatureNow(hash, _signature.signature), "Invalid Signer");
        _;
    }
}
