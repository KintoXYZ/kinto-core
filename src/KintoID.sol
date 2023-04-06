// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/* External Imports */
import "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/extensions/ERC1155SupplyUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import "@openzeppelin/contracts-upgradeable/utils/structs/BitMapsUpgradeable.sol";
import {IKintoID} from "./interfaces/IKintoID.sol";

// import "forge-std/console2.sol";


/**
 * @title Kinto ID
 * @dev The Kinto ID predeploy provides an interface to access all the ID functionality from the L2.
 */
contract KintoID is Initializable, ERC1155Upgradeable, AccessControlUpgradeable, ERC1155SupplyUpgradeable, UUPSUpgradeable, IKintoID {
    using BitMapsUpgradeable for BitMapsUpgradeable.BitMap;
    using ECDSAUpgradeable for bytes32;
    using SignatureChecker for address;

    /* ============ Events ============ */
    event TraitAdded(address indexed _to, uint8 _traitIndex, uint256 _timestamp);
    event TraitRemoved(address indexed _to, uint8 _traitIndex, uint256 _timestamp);
    event SanctionAdded(address indexed _to, uint8 _sanctionIndex, uint256 _timestamp);
    event SanctionRemoved(address indexed _to, uint8 _sanctionIndex, uint256 _timestamp);
    event AccountsMonitoredAt(address indexed _signer, uint256 _accountsCount, uint256 _timestamp);

    /* ============ Constants ============ */
    bytes32 public override constant KYC_PROVIDER_ROLE = keccak256("KYC_PROVIDER_ROLE");
    bytes32 public override constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    uint8 public override constant KYC_TOKEN_ID = 1;

    // We'll monitor the whole list every single day and update it
    uint256 public override lastMonitoredAt;

    /* ============ State Variables ============ */

    // Metadata for each minted token
    mapping(address => IKintoID.Metadata) private kycmetas;

    /// @dev We include a nonce in every hashed message, and increment the nonce as part of a
    /// state-changing operation, so as to prevent replay attacks, i.e. the reuse of a signature.
    mapping(address => uint256) public override nonces;

    // 256 traits max
    // 256 countries max. Currently, 192 countries exist

    /* ============ Modifiers ============ */


    /* ============ Constructor & Initializers ============ */

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() initializer public {
        __ERC1155_init("https://mamorilabs.com/metadata/{id}.json"); // pinata, ipfs
        __AccessControl_init();
        __ERC1155Supply_init();
        __UUPSUpgradeable_init();

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(KYC_PROVIDER_ROLE, msg.sender);
        _setupRole(UPGRADER_ROLE, msg.sender);
        lastMonitoredAt = block.timestamp;
    }

    /**
     * @dev Authorize the upgrade. Only by the upgrader role.
     * @param newImplementation address of the new implementation
     */
    // This function is called by the proxy contract when the implementation is upgraded
    function _authorizeUpgrade(address newImplementation) internal onlyRole(UPGRADER_ROLE) override {}

    /* ============ Token name, symbol & URI ============ */

    /**
     * @dev Gets the token name.
     * @return string representing the token name
     */
    function name() external pure override returns (string memory) {
        return "Kinto ID";
    }

    /**
     * @dev Gets the token symbol.
     * @return string representing the token symbol
     */
    function symbol() external pure override returns (string memory) {
        return "KINID";
    }

    /**
     * @dev Sets the token URI. Only by the admin role.
     * @param newuri representing the token URI.
     */
    function setURI(string memory newuri) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        _setURI(newuri);
    }

    /* ============ Mint & Burn ============ */

    /**
     * @dev Mints a new individual KYC token.
     * @param _signatureData Signature data
     * @param _traits Traits to be added to the account.
     */
    function mintIndividualKyc(IKintoID.SignatureData calldata _signatureData, uint8[] memory _traits) external override {
        mintTo(KYC_TOKEN_ID, _signatureData,_traits, true);
    }

    /**
     * @dev Mints a new company KYC token.
     * @param _signatureData Signature data
     * @param _traits Traits to be added to the account.
     */
    function mintCompanyKyc(IKintoID.SignatureData calldata _signatureData, uint8[] memory _traits) external override {
        mintTo(KYC_TOKEN_ID, _signatureData, _traits, false);
    }

    /**
     * @dev Mints a new token to the given account.
     * @param _tokenId Token ID to be minted
     * @param _signatureData Signature data
     * @param _traits Traits to be added to the account.
     * @param _indiv Whether the account is individual or a company.
    */
    function mintTo(uint8 _tokenId, IKintoID.SignatureData calldata _signatureData, uint8[] memory _traits, bool _indiv) private
      onlySignerVerified(_tokenId, _signatureData) {
       require(balanceOf(_signatureData.account, _tokenId) == 0, "Balance before mint must be 0");

       Metadata storage meta = kycmetas[_signatureData.account];
       meta.mintedAt = block.timestamp;
       meta.individual = _indiv;

       for (uint16 i = 0; i < _traits.length; i++) {
           meta.traits.set(_traits[i]);
       }

       _mint(_signatureData.account, _tokenId, 1, "");
       nonces[_signatureData.account]++;
    }

    /* ============ Burn ============ */

    /**
     * @dev Burns a KYC token.
     * @param _signatureData Signature data
     */
    function burnKYC(SignatureData calldata _signatureData) external override {
        burn(KYC_TOKEN_ID, _signatureData);
    }

    /**
     * @dev Burns a token.
     * @param _tokenId  token ID to be burned
     * @param _signatureData Signature data
     */
    function burn(uint256 _tokenId, SignatureData calldata _signatureData) private onlySignerVerified(_tokenId, _signatureData) {
        require(balanceOf(_signatureData.account, _tokenId) > 0, "Nothing to burn");
        _burn(_signatureData.account, _tokenId, 1);
        nonces[_signatureData.account] += 1;
        require(balanceOf(_signatureData.account, _tokenId) == 0, "Balance after burn must be 0");
    }

    /* ============ Sanctions & traits ============ */

    /**
     * @dev Monitors the account. Only by the KYC provider role.
     */
    function monitor(address[] memory _accounts, IKintoID.MonitorUpdateData[][] memory _traitsAndSanctions) external override onlyRole(KYC_PROVIDER_ROLE) {
        require(_accounts.length == _traitsAndSanctions.length, "Length mismatch");
        require(_accounts.length <= 200, "Too many accounts to monitor at once");
        for (uint8 i = 0; i < _accounts.length; i+= 1) {
            require(balanceOf(_accounts[i], 1) > 0, "Invalid account address");
            Metadata storage meta = kycmetas[_accounts[i]];
            meta.updatedAt = block.timestamp;
            for (uint8 j = 0; j < _traitsAndSanctions[i].length; j+= 1) {
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
        lastMonitoredAt = block.timestamp;
        emit AccountsMonitoredAt(msg.sender, _accounts.length, block.timestamp);
    }

    /**
     * @dev Adds a trait to the account. Only by the KYC provider role.
     * @param _account  account to be added the trait to.
     * @param _traitId trait id to be added.
     */
    function addTrait(address _account, uint8 _traitId) public override onlyRole(KYC_PROVIDER_ROLE) {
        Metadata storage meta = kycmetas[_account];
        if (!meta.traits.get(_traitId)) {
          meta.traits.set(_traitId);
          meta.updatedAt = block.timestamp;
          emit TraitAdded(_account, _traitId, block.timestamp);
        }
    }

    /**
     * @dev Removes a trait from the account. Only by the KYC provider role.
     * @param _account  account to be removed the trait from.
     * @param _traitId trait id to be removed.
     */
    function removeTrait(address _account, uint8 _traitId) public override onlyRole(KYC_PROVIDER_ROLE) {
        Metadata storage meta = kycmetas[_account];

        if (meta.traits.get(_traitId)) {
            meta.traits.unset(_traitId);
            meta.updatedAt = block.timestamp;
            emit TraitRemoved(_account, _traitId, block.timestamp);
        }
    }

    /**
     * @dev Adds a sanction to the account. Only by the KYC provider role.
     * @param _account  account to be added the sanction to.
     * @param _countryId country id to be added.
     */
    function addSanction(address _account, uint8 _countryId) public override onlyRole(KYC_PROVIDER_ROLE) {
        Metadata storage meta = kycmetas[_account];
        if (!meta.sanctions.get(_countryId)) {
            meta.sanctions.set(_countryId);
            meta.sanctionsCount += 1;
            meta.updatedAt = block.timestamp;
            emit SanctionAdded(_account, _countryId, block.timestamp);
        }
    }

    /**
     * @dev Removes a sanction from the account. Only by the KYC provider role.
     * @param _account  account to be removed the sanction from.
     * @param _countryId country id to be removed.
     */
    function removeSanction(address _account, uint8 _countryId) public override onlyRole(KYC_PROVIDER_ROLE) {
        Metadata storage meta = kycmetas[_account];
        if (meta.sanctions.get(_countryId)) {
            meta.sanctions.unset(_countryId);
            meta.sanctionsCount -= 1;
            meta.updatedAt = block.timestamp;
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
        return balanceOf(_account, KYC_TOKEN_ID) > 0;
    }

    /**
     * @dev Returns whether the account has been monitored in the last x days.
     * @param _days Days to be checked.
     * @return true if the account has been monitored in the last x days.
    */
    function isSanctionsMonitored(uint32 _days) public view override returns(bool) {
        return block.timestamp - lastMonitoredAt < _days * (1 days);
    }

    /**
     * @dev Returns whether the account is sanctions safe.
     * @param _account account to be checked.
     * @return true if the account is sanctions safe.
     */
    function isSanctionsSafe(address _account) external view override returns (bool) {
        return isSanctionsMonitored(7) && kycmetas[_account].sanctionsCount == 0;
    }

    /**
     * @dev Returns whether the account is sanctions safe in a given country.
     * @param _account account to be checked.
     * @param _countryId country id to be checked.
     * @return true if the account is sanctions safe in a given country.
     */
    function isSanctionsSafeIn(address _account, uint8 _countryId) external view override returns (bool) {
        return isSanctionsMonitored(7) && !kycmetas[_account].sanctions.get(_countryId);
    }

    /**
     * @dev Returns whether the KYC account is a company
     * @param _account account to be checked.
     * @return true if the account is a company.
     */
    function isCompany(address _account) external view override returns (bool) {
        return !kycmetas[_account].individual;
    }

    /**
     * @dev Returns whether the KYC account is an individual
     * @param _account account to be checked.
     * @return true if the account is an indivdual.
     */
    function isIndividual(address _account) external view override returns (bool) {
        return kycmetas[_account].individual;
    }

    /**
     * @dev Returns the timestamp when the KYC token was minted
     * @param _account account to be checked.
     * @return timestamp when the KYC token was minted.
     */
    function mintedAt(address _account) external view override returns (uint256) {
        return kycmetas[_account].mintedAt;
    }

    /**
     * @dev Returns whether the account has a given trait.
     * @param _account account to be checked.
     * @param index index of the trait to be checked.
     * @return true if the account has the trait.
     */
    function hasTrait(address _account, uint8 index) external view override returns (bool) {
        return kycmetas[_account].traits.get(index);
    }

    /**
     * @dev Returns an array of 256 booleans representing the traits of the account.
     * @param _account account to be checked.
     * @return array of 256 booleans representing the traits of the account.
     */
    function traits(address _account) external view override returns (bool[] memory) {
        BitMapsUpgradeable.BitMap storage tokenTraits = kycmetas[_account].traits;
        bool[] memory result = new bool[](256);
        for (uint256 i = 0; i < 256; i++) {
            result[i] = tokenTraits.get(i);
        }
        return result;
    }

    /* ============ Signature Recovery ============ */

    /**
     * @dev Check that the signature is valid and the sender is a valid KYC provider.
     * @param _id id of the token to be signed.
     * @param _signature signature to be recovered.
     */
    modifier onlySignerVerified(
      uint256 _id,
      IKintoID.SignatureData calldata _signature
    ) {
        require(block.timestamp < _signature.expiresAt, "Signature has expired");
        require(nonces[_signature.signer] == _signature.nonce, "Invalid Nonce");
        require(hasRole(KYC_PROVIDER_ROLE, msg.sender), "Invalid Provider");

        bytes32 hash = keccak256(
          abi.encodePacked(
            "\x19\x01",   // EIP-191 header
            keccak256(abi.encode(
                _signature.signer,
                address(this),
                _signature.account,
                _id,
                _signature.expiresAt,
                nonces[_signature.signer],
                bytes32(block.chainid)
            ))
          )
        ).toEthSignedMessageHash();

        require(
          _signature.signer.isValidSignatureNow(hash, _signature.signature),
          "Invalid Signer"
        );
        _;
    }

    /* ============ Disable token transfers ============ */

    /**
     * @dev Hook that is called before any token transfer. Allow only mints and burns, no transfers.
     * @param operator address which called `safeTransferFrom` function
     * @param from source address
     * @param to target address
     * @param ids ids of the token type
     * @param amounts transfer amounts
     * @param data additional data with no specified format
     */
    function _beforeTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal override(ERC1155Upgradeable, ERC1155SupplyUpgradeable) {
        require(
          (from == address(0) && to != address(0)) || (from != address(0) && to == address(0)),
          "Only mint or burn transfers are allowed"
        );
        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);
    }

    /* ============ Interface ============ */

    /**
     * @dev Returns whether the contract implements the interface defined by the id
     * @param interfaceId id of the interface to be checked.
     * @return true if the contract implements the interface defined by the id.
    */
    function supportsInterface(bytes4 interfaceId) public view override(ERC1155Upgradeable, AccessControlUpgradeable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
