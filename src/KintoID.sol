// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

/* External Imports */
import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import "@openzeppelin/contracts-upgradeable/utils/structs/BitMapsUpgradeable.sol";

import {IKintoID} from "./interfaces/IKintoID.sol";
import {IFaucet} from "./interfaces/IFaucet.sol";

/**
 * @title Kinto ID
 * @dev The Kinto ID predeploy provides an interface to access all the ID functionality from the L2.
 */
contract KintoID is
    Initializable,
    ERC721Upgradeable,
    ERC721EnumerableUpgradeable,
    ERC721BurnableUpgradeable,
    AccessControlUpgradeable,
    UUPSUpgradeable,
    IKintoID
{
    using BitMapsUpgradeable for BitMapsUpgradeable.BitMap;
    using ECDSAUpgradeable for bytes32;
    using SignatureChecker for address;

    /* ============ Events ============ */
    event TraitAdded(address indexed _to, uint16 _traitIndex, uint256 _timestamp);
    event TraitRemoved(address indexed _to, uint16 _traitIndex, uint256 _timestamp);
    event SanctionAdded(address indexed _to, uint16 _sanctionIndex, uint256 _timestamp);
    event SanctionRemoved(address indexed _to, uint16 _sanctionIndex, uint256 _timestamp);
    event AccountsMonitoredAt(address indexed _signer, uint256 _accountsCount, uint256 _timestamp);

    /* ============ Constants & Immutables ============ */

    bytes32 public constant override KYC_PROVIDER_ROLE = keccak256("KYC_PROVIDER_ROLE");
    bytes32 public constant override UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    /* ============ State Variables ============ */

    uint256 private _nextTokenId;

    // We'll monitor the whole list every single day and update it
    uint256 public override lastMonitoredAt;

    // Metadata for each minted token
    mapping(address => IKintoID.Metadata) internal _kycmetas;

    /// @dev We include a nonce in every hashed message, and increment the nonce as part of a
    /// state-changing operation, so as to prevent replay attacks, i.e. the reuse of a signature.
    mapping(address => uint256) public override nonces;

    bytes32 public override domainSeparator;

    // Indicates which accounts are allowed to transfer their Kinto ID to another account
    mapping(address => address) public override recoveryTargets;

    address public immutable override walletFactory;
    address public immutable override faucet;
    /* ============ Constructor & Initializers ============ */

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address _walletFactory, address _faucet) {
        _disableInitializers();
        walletFactory = _walletFactory;
        faucet = _faucet;
    }

    function initialize() external initializer {
        __ERC721_init("Kinto ID", "KINTOID");
        __ERC721Enumerable_init();
        __ERC721Burnable_init();
        __AccessControl_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(KYC_PROVIDER_ROLE, msg.sender);
        _grantRole(UPGRADER_ROLE, msg.sender);

        lastMonitoredAt = block.timestamp;
        domainSeparator = _domainSeparator();
    }

    /**
     * @dev Authorize the upgrade. Only by the upgrader role.
     * @param newImplementation address of the new implementation
     */
    // This function is called by the proxy contract when the implementation is upgraded
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}

    /* ============ Token name, symbol & URI ============ */

    /**
     * @dev Gets the token name.
     * @return string representing the token name
     */
    function name() public pure override(ERC721Upgradeable, IKintoID) returns (string memory) {
        return "Kinto ID";
    }

    /**
     * @dev Gets the token symbol.
     * @return string representing the token symbol
     */
    function symbol() public pure override(ERC721Upgradeable, IKintoID) returns (string memory) {
        return "KINTOID";
    }

    /**
     * @dev Returns the base token URI. ID is appended
     * @return token URI.
     */
    function _baseURI() internal pure override returns (string memory) {
        return "https://kinto.xyz/api/v1/nft-kinto-id/";
    }

    /* ============ Mint & Burn ============ */

    /**
     * @dev Mints a new individual KYC token.
     * @param _signatureData Signature data
     * @param _traits Traits to be added to the account.
     */
    function mintIndividualKyc(IKintoID.SignatureData calldata _signatureData, uint16[] calldata _traits)
        external
        override
    {
        _nextTokenId++;
        _mintTo(_nextTokenId, _signatureData, _traits, true);
    }

    /**
     * @dev Mints a new company KYC token.
     * @param _signatureData Signature data
     * @param _traits Traits to be added to the account.
     */
    function mintCompanyKyc(IKintoID.SignatureData calldata _signatureData, uint16[] calldata _traits)
        external
        override
    {
        _nextTokenId++;
        _mintTo(_nextTokenId, _signatureData, _traits, false);
    }

    /**
     * @dev Mints a new token to the given account.
     * @param _tokenId Token ID to be minted
     * @param _signatureData Signature data
     * @param _traits Traits to be added to the account.
     * @param _indiv Whether the account is individual or a company.
     */
    function _mintTo(
        uint256 _tokenId,
        IKintoID.SignatureData calldata _signatureData,
        uint16[] calldata _traits,
        bool _indiv
    ) private onlySignerVerified(_signatureData) {
        if (balanceOf(_signatureData.signer) > 0) revert BalanceNotZero();

        Metadata storage meta = _kycmetas[_signatureData.signer];
        meta.mintedAt = block.timestamp;
        meta.updatedAt = block.timestamp;
        meta.individual = _indiv;

        for (uint256 i = 0; i < _traits.length; i++) {
            meta.traits.set(_traits[i]);
        }

        nonces[_signatureData.signer]++;
        _safeMint(_signatureData.signer, _tokenId);
        IFaucet(faucet).claimOnCreation(_signatureData.signer);
    }

    /* ============ Burn ============ */

    /**
     * @dev Transfers the NFT from the old account to the new account
     * @param _from Old address
     * @param _to New address
     */
    function transferOnRecovery(address _from, address _to) external override {
        require(balanceOf(_from) > 0 && balanceOf(_to) == 0, "Invalid transfer");
        require(
            msg.sender == walletFactory || hasRole(DEFAULT_ADMIN_ROLE, msg.sender),
            "Only the wallet factory or admins can trigger this"
        );
        recoveryTargets[_from] = _to;
        _transfer(_from, _to, tokenOfOwnerByIndex(_from, 0));
        recoveryTargets[_from] = address(0);
    }

    /**
     * @dev Burns a KYC token base ERC721 burn method. Override to disable.
     */
    function burn(uint256 /* tokenId */ ) public pure override {
        if (true) revert MethodNotAllowed("Use burnKYC instead");
    }

    /**
     * @dev Burns a KYC token.
     * @param _signatureData Signature data
     */
    function burnKYC(SignatureData calldata _signatureData) external override onlySignerVerified(_signatureData) {
        if (balanceOf(_signatureData.signer) == 0) revert NothingToBurn();

        nonces[_signatureData.signer] += 1;
        _burn(tokenOfOwnerByIndex(_signatureData.signer, 0));
        if (balanceOf(_signatureData.signer) > 0) revert BalanceNotZero();

        // Update metadata after burning the token
        Metadata storage meta = _kycmetas[_signatureData.signer];
        meta.mintedAt = 0;
        meta.updatedAt = 0;
    }

    /* ============ Sanctions & traits ============ */

    /**
     * @dev Updates the accounts that have flags or sanctions. Only by the KYC provider role.
     * This method will be called with empty accounts if there are not traits/sanctions to add.
     * Realistically only 1% of the accounts will ever be flagged and a small % of this will happen in the same day.
     * As a consequence, 200 accounts should be enough even when we have 100k users.
     * 200 accounts should fit in the 8M gas limit.
     * @param _accounts  accounts to be updated.
     * @param _traitsAndSanctions traits and sanctions to be updated.
     */
    function monitor(address[] calldata _accounts, IKintoID.MonitorUpdateData[][] calldata _traitsAndSanctions)
        external
        override
        onlyRole(KYC_PROVIDER_ROLE)
    {
        if (_accounts.length != _traitsAndSanctions.length) revert LengthMismatch();
        if (_accounts.length > 200) revert AccountsAmountExceeded();

        uint256 time = block.timestamp;

        for (uint256 i = 0; i < _accounts.length; i += 1) {
            Metadata storage meta = _kycmetas[_accounts[i]];

            if (balanceOf(_accounts[i]) == 0) {
                continue;
            }
            meta.updatedAt = block.timestamp;
            for (uint256 j = 0; j < _traitsAndSanctions[i].length; j += 1) {
                IKintoID.MonitorUpdateData memory updateData = _traitsAndSanctions[i][j];
                if (updateData.isTrait && updateData.isSet) {
                    addTrait(_accounts[i], updateData.index);
                } else if (updateData.isTrait && !updateData.isSet) {
                    removeTrait(_accounts[i], updateData.index);
                } else if (!updateData.isTrait && updateData.isSet) {
                    addSanction(_accounts[i], updateData.index);
                } else {
                    removeSanction(_accounts[i], updateData.index);
                }
            }
        }

        lastMonitoredAt = time;
        emit AccountsMonitoredAt(msg.sender, _accounts.length, time);
    }

    /**
     * @dev Adds a trait to the account. Only by the KYC provider role.
     * @param _account  account to be added the trait to.
     * @param _traitId trait id to be added.
     */
    function addTrait(address _account, uint16 _traitId) public override onlyRole(KYC_PROVIDER_ROLE) {
        if (balanceOf(_account) == 0) revert KYCRequired();

        Metadata storage meta = _kycmetas[_account];
        if (!meta.traits.get(_traitId)) {
            meta.traits.set(_traitId);
            meta.updatedAt = block.timestamp;
            lastMonitoredAt = block.timestamp;
            emit TraitAdded(_account, _traitId, block.timestamp);
        }
    }

    /**
     * @dev Removes a trait from the account. Only by the KYC provider role.
     * @param _account  account to be removed the trait from.
     * @param _traitId trait id to be removed.
     */
    function removeTrait(address _account, uint16 _traitId) public override onlyRole(KYC_PROVIDER_ROLE) {
        if (balanceOf(_account) == 0) revert KYCRequired();
        Metadata storage meta = _kycmetas[_account];

        if (meta.traits.get(_traitId)) {
            meta.traits.unset(_traitId);
            meta.updatedAt = block.timestamp;
            lastMonitoredAt = block.timestamp;
            emit TraitRemoved(_account, _traitId, block.timestamp);
        }
    }

    /**
     * @dev Adds a sanction to the account. Only by the KYC provider role.
     * @param _account  account to be added the sanction to.
     * @param _countryId country id to be added.
     */
    function addSanction(address _account, uint16 _countryId) public override onlyRole(KYC_PROVIDER_ROLE) {
        if (balanceOf(_account) == 0) revert KYCRequired();
        Metadata storage meta = _kycmetas[_account];
        if (!meta.sanctions.get(_countryId)) {
            meta.sanctions.set(_countryId);
            meta.sanctionsCount += 1;
            meta.updatedAt = block.timestamp;
            lastMonitoredAt = block.timestamp;
            emit SanctionAdded(_account, _countryId, block.timestamp);
        }
    }

    /**
     * @dev Removes a sanction from the account. Only by the KYC provider role.
     * @param _account  account to be removed the sanction from.
     * @param _countryId country id to be removed.
     */
    function removeSanction(address _account, uint16 _countryId) public override onlyRole(KYC_PROVIDER_ROLE) {
        if (balanceOf(_account) == 0) revert KYCRequired();
        Metadata storage meta = _kycmetas[_account];
        if (meta.sanctions.get(_countryId)) {
            meta.sanctions.unset(_countryId);
            meta.sanctionsCount -= 1;
            meta.updatedAt = block.timestamp;
            lastMonitoredAt = block.timestamp;
            emit SanctionRemoved(_account, _countryId, block.timestamp);
        }
    }

    /* ============ View Functions ============ */

    /**
     * @dev Returns whether the account holder is KYCd
     * @param _account account to be checked.
     * @return true if the account has KYC token.
     */
    function isKYC(address _account) external view override returns (bool) {
        return balanceOf(_account) > 0 && isSanctionsSafe(_account);
    }

    /**
     * @dev Returns whether the account was monitored in the last x days.
     * @param _days Days to be checked.
     * @return true if the account was monitored in the last x days.
     */
    function isSanctionsMonitored(uint32 _days) public view virtual override returns (bool) {
        return block.timestamp - lastMonitoredAt < _days * (1 days);
    }

    /**
     * @dev Returns whether the account is sanctions safe.
     * @param _account account to be checked.
     * @return true if the account is sanctions safe.
     */
    function isSanctionsSafe(address _account) public view virtual override returns (bool) {
        return isSanctionsMonitored(7) && _kycmetas[_account].sanctionsCount == 0;
    }

    /**
     * @dev Returns whether the account is sanctions safe in a given country.
     * @param _account account to be checked.
     * @param _countryId country id to be checked.
     * @return true if the account is sanctions safe in a given country.
     */
    function isSanctionsSafeIn(address _account, uint16 _countryId) external view virtual override returns (bool) {
        return isSanctionsMonitored(7) && !_kycmetas[_account].sanctions.get(_countryId);
    }

    /**
     * @dev Returns whether the KYC account is a company
     * @param _account account to be checked.
     * @return true if the account is a company.
     */
    function isCompany(address _account) external view override returns (bool) {
        return !_kycmetas[_account].individual;
    }

    /**
     * @dev Returns whether the KYC account is an individual
     * @param _account account to be checked.
     * @return true if the account is an indivdual.
     */
    function isIndividual(address _account) external view override returns (bool) {
        return _kycmetas[_account].individual;
    }

    /**
     * @dev Returns the timestamp when the KYC token was minted
     * @param _account account to be checked.
     * @return timestamp when the KYC token was minted.
     */
    function mintedAt(address _account) external view override returns (uint256) {
        return _kycmetas[_account].mintedAt;
    }

    /**
     * @dev Returns whether the account has a given trait.
     * @param _account account to be checked.
     * @param index index of the trait to be checked.
     * @return true if the account has the trait.
     */
    function hasTrait(address _account, uint16 index) external view override returns (bool) {
        return _kycmetas[_account].traits.get(index);
    }

    /**
     * @dev Returns an array of 256 booleans representing the traits of the account.
     * @param _account account to be checked.
     * @return array of 256 booleans representing the traits of the account.
     */
    function traits(address _account) external view override returns (bool[] memory) {
        BitMapsUpgradeable.BitMap storage tokenTraits = _kycmetas[_account].traits;
        bool[] memory result = new bool[](256);
        for (uint256 i = 0; i < 256; i++) {
            result[i] = tokenTraits.get(i);
        }
        return result;
    }

    /* ============ Signature Recovery ============ */

    /**
     * @dev Check that the signature is valid and the sender is a valid KYC provider.
     * @param _signature signature to be recovered.
     */
    modifier onlySignerVerified(IKintoID.SignatureData calldata _signature) {
        if (block.timestamp >= _signature.expiresAt) revert SignatureExpired();
        if (nonces[_signature.signer] != _signature.nonce) revert InvalidNonce();
        if (!hasRole(KYC_PROVIDER_ROLE, msg.sender)) revert InvalidProvider();

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

    /* ============ EIP-712 Helpers ============ */

    function _domainSeparator() internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("KintoID")), // this contract's name
                keccak256(bytes("1")), // version
                _getChainID(),
                address(this)
            )
        );
    }

    function _hashSignatureData(SignatureData memory signatureData) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                keccak256("SignatureData(address signer,uint256 nonce,uint256 expiresAt)"),
                signatureData.signer,
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

    /* ============ Disable token transfers ============ */

    /**
     * @dev Hook that is called before any token transfer. Allow only mints and burns, no transfers.
     * @param from source address
     * @param to target address
     * @param batchSize The first id
     */
    function _beforeTokenTransfer(address from, address to, uint256 firstTokenId, uint256 batchSize)
        internal
        virtual
        override(ERC721Upgradeable, ERC721EnumerableUpgradeable)
    {
        if (
            (from == address(0) || recoveryTargets[from] != to || !isSanctionsSafe(from))
                && (from != address(0) || to == address(0)) && (from == address(0) || to != address(0))
        ) revert OnlyMintBurnOrTransfer();
        super._beforeTokenTransfer(from, to, firstTokenId, batchSize);
    }

    /* ============ Interface ============ */

    /**
     * @dev Returns whether the contract implements the interface defined by the id
     * @param interfaceId id of the interface to be checked.
     * @return true if the contract implements the interface defined by the id.
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721Upgradeable, ERC721EnumerableUpgradeable, AccessControlUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}

contract KintoIDV8 is KintoID {
    constructor(address _walletFactory, address _faucet) KintoID(_walletFactory, _faucet) {}
}
