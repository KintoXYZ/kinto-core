// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/* External Imports */
import "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/extensions/ERC1155SupplyUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/structs/BitMapsUpgradeable.sol";
import {IKintoID} from "./interfaces/IKintoID.sol";
import {SignatureChecker} from './lib/SignatureChecker.sol';

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
    event AccountsMonitoredAt(address indexed _signer, uint256 _timestamp);

    /* ============ Constants ============ */
    bytes32 public override constant KYC_PROVIDER_ROLE = keccak256("KYC_PROVIDER_ROLE");

    uint8 public override constant KYC_TOKEN_ID = 1;

    // We'll monitor the whole list every single day and update it
    uint256 public override lastMonitoredAt;

    /* ============ State Variables ============ */

    // Metadata for each minted token
    mapping(address => IKintoID.Metadata) private kycmetas;

    /// @dev We include a nonce in every hashed message, and increment the nonce as part of a
    /// state-changing operation, so as to prevent replay attacks, i.e. the reuse of a signature.
    mapping(address => uint256) private nonces;

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
        lastMonitoredAt = block.timestamp;
    }

    /**
    *
    */
    function _authorizeUpgrade(address newImplementation) internal onlyRole(DEFAULT_ADMIN_ROLE) override {}

    /* ============ Token name, symbol & URI ============ */

    /**
     * @dev Gets the token name.
     * @return string representing the token name
     */
    function name() external pure override returns (string memory) {
        return "OM - ID";
    }

    /**
     * @dev Gets the token symbol.
     * @return string representing the token symbol
     */
    function symbol() external pure override returns (string memory) {
        return "OMID";
    }

    function setURI(string memory newuri) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        _setURI(newuri);
    }

    /* ============ Mint & Burn ============ */

    function mintIndividualKyc(IKintoID.SignatureData calldata _signatureData, uint8[] memory _traits) external override {
        mintTo(KYC_TOKEN_ID, _signatureData,_traits, true);
    }

    function mintCompanyKyc(IKintoID.SignatureData calldata _signatureData, uint8[] memory _traits) external override {
        mintTo(KYC_TOKEN_ID, _signatureData, _traits, false);
    }

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

    function burnKYC(SignatureData calldata _signatureData) external override {
        burn(KYC_TOKEN_ID, _signatureData);
    }

    function burn(uint256 _tokenId, SignatureData calldata _signatureData) private onlySignerVerified(_tokenId, _signatureData) {
        require(balanceOf(_signatureData.account, _tokenId) > 0, "Nothing to burn");
        nonces[_signatureData.account] += 1;
        _burn(_signatureData.account, _tokenId, 1);
        require(balanceOf(_signatureData.account, _tokenId) == 0, "Balance after burn must be 0");
    }

    /* ============ Sanctions & traits ============ */

    function monitor() external override onlyRole(KYC_PROVIDER_ROLE) {
        lastMonitoredAt = block.timestamp;
        emit AccountsMonitoredAt(msg.sender, block.timestamp);
    }

    function addTrait(address _account, uint8 _traitId) external override onlyRole(KYC_PROVIDER_ROLE) {
        Metadata storage meta = kycmetas[_account];
        if (!meta.traits.get(_traitId)) {
          meta.traits.set(_traitId);
          meta.updatedAt = block.timestamp;
          emit TraitAdded(_account, _traitId, block.timestamp);
        }
    }

    function removeTrait(address _account, uint8 _traitId) external override onlyRole(KYC_PROVIDER_ROLE) {
        Metadata storage meta = kycmetas[_account];

        if (meta.traits.get(_traitId)) {
            meta.traits.unset(_traitId);
            meta.updatedAt = block.timestamp;
            emit TraitRemoved(_account, _traitId, block.timestamp);
        }
    }

    function addSanction(address _account, uint8 _countryId) external override onlyRole(KYC_PROVIDER_ROLE) {
        Metadata storage meta = kycmetas[_account];
        if (!meta.sanctions.get(_countryId)) {
            meta.sanctions.set(_countryId);
            meta.sanctionsCount += 1;
            meta.updatedAt = block.timestamp;
            emit SanctionAdded(_account, _countryId, block.timestamp);
        }
    }

    function removeSanction(address _account, uint8 _countryId) external override onlyRole(KYC_PROVIDER_ROLE) {
        Metadata storage meta = kycmetas[_account];
        if (meta.sanctions.get(_countryId)) {
            meta.sanctions.unset(_countryId);
            meta.sanctionsCount -= 1;
            meta.updatedAt = block.timestamp;
            emit SanctionRemoved(_account, _countryId, block.timestamp);
        }
    }

    /* ============ View Functions ============ */

    function isKYC(address _account) external view override returns (bool) {
        return balanceOf(_account, 1) > 0;
    }

    function isSanctionsMonitored(uint32 _days) public view override returns(bool) {
        return block.timestamp - lastMonitoredAt < _days * (1 days);
    }

    function isSanctionsSafe(address _account) external view override returns (bool) {
        return isSanctionsMonitored(7) && kycmetas[_account].sanctionsCount == 0;
    }

    function isSanctionsSafeIn(address _account, uint8 _countryId) external view override returns (bool) {
        return isSanctionsMonitored(7) && !kycmetas[_account].sanctions.get(_countryId);
    }

    function isCompany(address _account) external view override returns (bool) {
        return !kycmetas[_account].individual;
    }

    function isIndividual(address _account) external view override returns (bool) {
        return kycmetas[_account].individual;
    }

    function mintedAt(address _account) external view override returns (uint256) {
        return kycmetas[_account].mintedAt;
    }

    function hasTrait(address _account, uint8 index) external view override returns (bool) {
        return kycmetas[_account].traits.get(index);
    }

    function traits(address _account) external view override returns (bool[] memory) {
        BitMapsUpgradeable.BitMap storage tokenTraits = kycmetas[_account].traits;
        // For all possible traits, see if the trait is set in the token, and if so, add
        // the index of the trait to our list of indexes.
        bool[] memory result = new bool[](256);
        for (uint256 i = 0; i < 256; i++) {
            result[i] = tokenTraits.get(i);
        }
        return result;
    }

    /* ============ Signature Recovery ============ */

    modifier onlySignerVerified(
      uint256 _id,
      IKintoID.SignatureData calldata _signature
    ) {
        require(block.timestamp < _signature.expiresAt, "Signature has expired");
        require(nonces[_signature.account] == _signature.nonce, "Invalid nonce");

        bytes32 hash = keccak256(
          abi.encodePacked(
            _signature.signer,
            address(this),
            _signature.account,
            _id,
            _signature.expiresAt,
            nonces[_signature.account],
            block.chainid
          )
        ).toEthSignedMessageHash();

        require(
          hasRole(KYC_PROVIDER_ROLE, msg.sender) &&
          _signature.signer.isValidSignatureNow(hash, _signature.signature),
          "Invalid signer"
        );
        _;
    }

    /* ============ Disable token transfers ============ */

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

    function supportsInterface(bytes4 interfaceId) public view override(ERC1155Upgradeable, AccessControlUpgradeable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
