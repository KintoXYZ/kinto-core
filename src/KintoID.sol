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

    /**
     * @notice Emitted when a trait is added to an account
     * @param _to Address receiving the trait
     * @param _traitIndex Index of the trait being added
     * @param _timestamp Time when the trait was added
     */
    event TraitAdded(address indexed _to, uint16 _traitIndex, uint256 _timestamp);

    /**
     * @notice Emitted when a trait is removed from an account
     * @param _to Address losing the trait
     * @param _traitIndex Index of the trait being removed
     * @param _timestamp Time when the trait was removed
     */
    event TraitRemoved(address indexed _to, uint16 _traitIndex, uint256 _timestamp);

    /**
     * @notice Emitted when a sanction is added to an account
     * @param _to Address receiving the sanction
     * @param _sanctionIndex Index of the sanction being added
     * @param _timestamp Time when the sanction was added
     */
    event SanctionAdded(address indexed _to, uint16 _sanctionIndex, uint256 _timestamp);

    /**
     * @notice Emitted when a sanction is removed from an account
     * @param _to Address losing the sanction
     * @param _sanctionIndex Index of the sanction being removed
     * @param _timestamp Time when the sanction was removed
     */
    event SanctionRemoved(address indexed _to, uint16 _sanctionIndex, uint256 _timestamp);

    /**
     * @notice Emitted when accounts are monitored for sanctions
     * @param _signer Address that performed the monitoring
     * @param _accountsCount Number of accounts monitored
     * @param _timestamp Time when monitoring was performed
     */
    event AccountsMonitoredAt(address indexed _signer, uint256 _accountsCount, uint256 _timestamp);

    /**
     * @notice Emitted when a sanction is confirmed by governance
     * @param account Address whose sanction was confirmed
     * @param timestamp Time when the sanction was confirmed
     */
    event SanctionConfirmed(address indexed account, uint256 timestamp);

    /* ============ Constants & Immutables ============ */

    /// @notice Role identifier for KYC providers
    bytes32 public constant override KYC_PROVIDER_ROLE = keccak256("KYC_PROVIDER_ROLE");

    /// @notice Role identifier for contract upgraders
    bytes32 public constant override UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    /// @notice Role identifier for governance actions
    bytes32 public constant override GOVERNANCE_ROLE = keccak256("GOVERNANCE_ROLE");

    /// @notice The period of time after which sanction is expired unless approved by governance
    uint256 public constant SANCTION_EXPIRY_PERIOD = 3 days;

    /// @notice The period of time during which additional sanctions can't be applied and user can exit, unless sanctions approved by governance
    uint256 public constant EXIT_WINDOW_PERIOD = 10 days;

    /// @notice Address of the wallet factory contract
    address public immutable override walletFactory;

    /// @notice Address of the faucet contract
    address public immutable override faucet;

    /* ============ State Variables ============ */

    /// @notice Counter for the next token ID to be minted
    uint256 private _nextTokenId;

    /// @notice Timestamp of the last sanction monitoring update
    uint256 public override lastMonitoredAt;

    /// @notice Mapping of addresses to their KYC metadata
    mapping(address => IKintoID.Metadata) internal _kycmetas;

    /// @notice Mapping of addresses to their current nonce for signature verification
    mapping(address => uint256) public override nonces;

    /// @notice EIP-712 domain separator
    bytes32 public override domainSeparator;

    /// @notice Mapping of accounts to their approved recovery target addresses
    mapping(address => address) public override recoveryTargets;

    /// @notice DEPRECATED: Previous wallet factory address
    address private __walletFactory;

    /// @notice Mapping of addresses to their last sanction application timestamp
    mapping(address => uint256) public sanctionedAt;

    /* ============ Constructor & Initializers ============ */

    /**
     * @notice Creates a new instance of the KintoID contract
     * @param _walletFactory Address of the KintoWalletFactory contract
     * @param _faucet Address of the Faucet contract
     */
    constructor(address _walletFactory, address _faucet) {
        _disableInitializers();
        walletFactory = _walletFactory;
        faucet = _faucet;
    }

    /**
     * @notice Initializes the contract with initial admin and role settings
     * @dev Sets up ERC721 metadata, grants initial roles, and initializes monitoring timestamp
     */
    function initialize() external initializer {
        __ERC721_init("Kinto ID", "KINTOID");
        __ERC721Enumerable_init();
        __ERC721Burnable_init();
        __AccessControl_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(KYC_PROVIDER_ROLE, msg.sender);
        _grantRole(UPGRADER_ROLE, msg.sender);
        _grantRole(GOVERNANCE_ROLE, msg.sender);

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
     * @notice Mints a new KYC token for an individual
     * @dev Can only be called by an approved KYC provider with valid signature
     * @param _signatureData The signature data for verification
     * @param _traits Array of trait IDs to assign to the account
     */
    function mintIndividualKyc(IKintoID.SignatureData calldata _signatureData, uint16[] calldata _traits)
        external
        override
    {
        _nextTokenId++;
        _mintTo(_nextTokenId, _signatureData, _traits, true);
    }

    /**
     * @notice Mints a new KYC token for a company
     * @dev Can only be called by an approved KYC provider with valid signature
     * @param _signatureData The signature data for verification
     * @param _traits Array of trait IDs to assign to the account
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
     * @notice Transfers KYC credentials during account recovery
     * @dev Only callable by wallet factory or admin role
     * @param _from Address to transfer from
     * @param _to Address to transfer to
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
     * @notice Burns a KYC token
     * @dev Can only be called by an approved KYC provider with valid signature
     * @param _signatureData The signature data for verification
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
     * @notice Updates sanctions and traits for multiple accounts
     * @dev Updates the accounts that have flags or sanctions. Only by the KYC provider role.
     * This method will be called with empty accounts if there are not traits/sanctions to add.
     * Realistically only 1% of the accounts will ever be flagged and a small % of this will happen in the same day.
     * As a consequence, 200 accounts should be enough even when we have 100k users.
     * 200 accounts should fit in the 8M gas limit.
     * @param _accounts Array of account addresses to update
     * @param _traitsAndSanctions Array of trait and sanction updates for each account
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
     * @notice Adds a trait to an account
     * @dev Only callable by KYC provider role
     * @param _account Address of the account
     * @param _traitId ID of the trait to add
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
     * @notice Removes a trait from an account
     * @dev Only callable by KYC provider role
     * @param _account Address of the account
     * @param _traitId ID of the trait to remove
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
     * @notice Adds a sanction to an account
     * @dev Only callable by KYC provider role. Initiates a 3-day confirmation period.
     * @param _account Address of the account
     * @param _countryId ID of the country issuing the sanction
     */
    function addSanction(address _account, uint16 _countryId) public override onlyRole(KYC_PROVIDER_ROLE) {
        if (balanceOf(_account) == 0) revert KYCRequired();

        // Check if account is in protection period (10 days from last sanction)
        uint256 lastSanctionTime = sanctionedAt[_account];
        if (lastSanctionTime != 0 && block.timestamp - lastSanctionTime < EXIT_WINDOW_PERIOD) {
            revert ExitWindowPeriod(_account, lastSanctionTime);
        }

        Metadata storage meta = _kycmetas[_account];
        if (!meta.sanctions.get(_countryId)) {
            meta.sanctions.set(_countryId);
            meta.sanctionsCount += 1;
            meta.updatedAt = block.timestamp;
            lastMonitoredAt = block.timestamp;
            emit SanctionAdded(_account, _countryId, block.timestamp);

            // Set the timestamp when the sanction was added
            sanctionedAt[_account] = block.timestamp;
        }
    }

    /**
     * @notice Removes a sanction from an account
     * @dev Only callable by KYC provider role
     * @param _account Address of the account
     * @param _countryId ID of the country whose sanction is being removed
     */
    function removeSanction(address _account, uint16 _countryId) public override onlyRole(KYC_PROVIDER_ROLE) {
        if (balanceOf(_account) == 0) revert KYCRequired();

        // Check if account is in protection period (10 days from last sanction)
        uint256 lastSanctionTime = sanctionedAt[_account];
        if (lastSanctionTime != 0 && block.timestamp - lastSanctionTime < EXIT_WINDOW_PERIOD) {
            revert ExitWindowPeriod(_account, lastSanctionTime);
        }

        Metadata storage meta = _kycmetas[_account];
        if (meta.sanctions.get(_countryId)) {
            meta.sanctions.unset(_countryId);
            meta.sanctionsCount -= 1;
            meta.updatedAt = block.timestamp;
            lastMonitoredAt = block.timestamp;
            emit SanctionRemoved(_account, _countryId, block.timestamp);

            // Reset sanction timestamp
            sanctionedAt[_account] = 0;
        }
    }

    /* ============ View Functions ============ */

    /**
     * @notice Checks if an account has passed KYC
     * @dev Returns false if the account has no token or has active sanctions
     * @param _account Address to check
     * @return bool True if the account is KYC verified and has no active sanctions
     */
    function isKYC(address _account) external view override returns (bool) {
        return balanceOf(_account) > 0 && isSanctionsSafe(_account);
    }

    /**
     * @notice Checks if sanctions monitoring is up to date
     * @param _days Number of days to consider for monitoring freshness
     * @return bool True if sanctions were monitored within the specified period
     */
    function isSanctionsMonitored(uint256 _days) public view virtual override returns (bool) {
        return block.timestamp - lastMonitoredAt < _days * (1 days);
    }

    /**
     * @notice Checks if an account has active sanctions
     * @dev Account is considered safe if sanctions are not confirmed within SANCTION_EXPIRY_PERIOD
     * @param _account Address to check
     * @return bool True if the account has no active sanctions
     */
    function isSanctionsSafe(address _account) public view virtual override returns (bool) {
        // If the sanction is not confirmed within SANCTION_EXPIRY_PERIOD, consider the account sanctions safe
        return isSanctionsMonitored(EXIT_WINDOW_PERIOD / (1 days))
            && (
                _kycmetas[_account].sanctionsCount == 0
                    || (sanctionedAt[_account] != 0 && (block.timestamp - sanctionedAt[_account]) > SANCTION_EXPIRY_PERIOD)
            );
    }

    /**
     * @notice Checks if an account is sanctioned in a specific country
     * @dev Account is considered safe if sanction is not confirmed within SANCTION_EXPIRY_PERIOD
     * @param _account Address to check
     * @param _countryId ID of the country to check sanctions for
     * @return bool True if the account is not sanctioned in the specified country
     */
    function isSanctionsSafeIn(address _account, uint16 _countryId) external view virtual override returns (bool) {
        // If the sanction is not confirmed within SANCTION_EXPIRY_PERIOD, consider the account sanctions safe
        return isSanctionsMonitored(EXIT_WINDOW_PERIOD / (1 days))
            && (
                !_kycmetas[_account].sanctions.get(_countryId)
                    || (sanctionedAt[_account] != 0 && (block.timestamp - sanctionedAt[_account]) > SANCTION_EXPIRY_PERIOD)
            );
    }

    /**
     * @notice Confirms a sanction, making it permanent
     * @dev Only callable by governance role. Reverts if no active sanction exists.
     * @param _account Address of the account whose sanction is being confirmed
     */
    function confirmSanction(address _account) external onlyRole(GOVERNANCE_ROLE) {
        // Check that there's an active sanction
        if (_kycmetas[_account].sanctionsCount == 0) {
            revert NoActiveSanction(_account);
        }

        // Reset sanction timestamp to make the sanction indefinite
        sanctionedAt[_account] = 0;
        emit SanctionConfirmed(_account, block.timestamp);
    }

    /**
     * @notice Checks if an account is registered as a company
     * @param _account Address to check
     * @return bool True if the account is registered as a company
     */
    function isCompany(address _account) external view override returns (bool) {
        return !_kycmetas[_account].individual;
    }

    /**
     * @notice Checks if an account is registered as an individual
     * @param _account Address to check
     * @return bool True if the account is registered as an individual
     */
    function isIndividual(address _account) external view override returns (bool) {
        return _kycmetas[_account].individual;
    }

    /**
     * @notice Gets the timestamp when an account's KYC was minted
     * @param _account Address to check
     * @return uint256 Timestamp when the KYC token was minted
     */
    function mintedAt(address _account) external view override returns (uint256) {
        return _kycmetas[_account].mintedAt;
    }

    /**
     * @notice Checks if an account has a specific trait
     * @param _account Address to check
     * @param index ID of the trait to check
     * @return bool True if the account has the specified trait
     */
    function hasTrait(address _account, uint16 index) external view override returns (bool) {
        return _kycmetas[_account].traits.get(index);
    }

    /**
     * @notice Gets all traits for an account
     * @param _account Address to check
     * @return bool[] Array of traits where true indicates the trait is present
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

contract KintoIDV10 is KintoID {
    constructor(address _walletFactory, address _faucet) KintoID(_walletFactory, _faucet) {}
}
