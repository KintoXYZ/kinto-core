// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

/* External Imports */
import "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/extensions/ERC1155SupplyUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/structs/BitMapsUpgradeable.sol";

/**
 * @title Kinto ID
 * @dev The Kinto ID predeploy provides an interface to access all the ID functionality from the L2.
 */
contract KintoID is Initializable, ERC1155Upgradeable, AccessControlUpgradeable, ERC1155SupplyUpgradeable, UUPSUpgradeable {
    using BitMapsUpgradeable for BitMapsUpgradeable.BitMap;
    /* ============ Events ============ */
    event TraitAdded(address indexed _to, uint8 _traitIndex, uint256 _timestamp);
    event TraitRemoved(address indexed _to, uint8 _traitIndex, uint256 _timestamp);
    event SanctionAdded(address indexed _to, uint8 _sanctionIndex, uint256 _timestamp);
    event SanctionRemoved(address indexed _to, uint8 _sanctionIndex, uint256 _timestamp);

    /* ============ Constants ============ */
    bytes32 public constant KYC_PROVIDER_ROLE = keccak256("KYC_PROVIDER_ROLE");

    uint8 public constant KYC_TOKEN_ID = 1;

    /* ============ Structs ============ */

    struct Metadata {
        uint256 mintedAt;
        uint8 sanctionsCount;
        bool individual;
        BitMapsUpgradeable.BitMap traits;
        BitMapsUpgradeable.BitMap sanctions;
    }

    /* ============ State Variables ============ */

    // Metadata for each minted token
    mapping(address => Metadata) private kycmeta;

    /// @dev We include a nonce in every hashed message, and increment the nonce as part of a
    /// state-changing operation, so as to prevent replay attacks, i.e. the reuse of a signature.
    mapping(address => uint256) public nonces;

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
    function name() external pure returns (string memory) {
        return "OM - ID";
    }

    /**
     * @dev Gets the token symbol.
     * @return string representing the token symbol
     */
    function symbol() external pure returns (string memory) {
        return "OMID";
    }

    function setURI(string memory newuri) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setURI(newuri);
    }

    /* ============ Mint & Burn ============ */

    function mintIndividualKyc(address _signer, address _recipient, uint256 _nonce, uint256 _expiresAt, uint8[] memory _traits, bytes calldata _signature) external
        override
    {
        mintTo(_signer, _recipient, _nonce, 1, _expiresAt, _traits, true, _signature);
    }

    function mintCompanyKyc(address _signer, address _recipient, uint256 _nonce, uint256 _expiresAt, uint8[] memory _traits, bytes calldata _signature) external
        override
    {
        mintTo(_signer, _recipient, _nonce, 1, _expiresAt, _traits, false, _signature);
    }

    function mintTo(address _signer, address _recipient, uint256 _nonce, uint256 _id, uint256 _expiresAt, uint8[] memory _traits, bool _indiv, bytes calldata _signature) public
        override
        onlySignerMintTo(_signer, _recipient, _nonce, _id, _expiresAt, _signature)
    {
        _mintTo(_recipient, _id, _traits, _indiv);
    }

    function _mintTo(address _mintToAddress, uint256 _id, uint8[] memory _traits, bool _indiv) private {
        require(balanceOf(_mintToAddress, _id) == 0, "Balance before mint must be 0");

        Metadata storage meta = metas[newItemId];
        meta.mintedAt = block.timestamp;
        meta.isIndividual = _indiv;

        for (uint16 i = 0; i < _traits.length; i++) {
            meta.traits.set(_traits[i]);
        }

        _mint(_mintToAddress, _id, 1, "");
        nonces[_mintToAddress]++;
    }

    /* ============ Burn ============ */

    function burn(
      address _account,
      uint256 _id,
      uint256 _expiresAt,
      bytes calldata _signature
    ) external override onlySigner(_account, _id, _expiresAt, _signature) {
      nonces[_account] += 1;
      _burn(_account, _id, 1);
      require(balanceOf(_account, _id) == 0, "Balance after burn must be 0");
    }

    /* ============ Sanctions & traits ============ */

    function addTrait(address _account, uint8 _traitId) external virtual onlyRole(KYC_PROVIDER_ROLE) {
        Metadata storage meta = metas[_account];
        if (!meta.traits.get(_traitId)) {
          meta.traits.set(_traitId);
          emit TraitAdded(_account, _traitId, block.timestamp);
        }
    }

    function removeTrait(address _account, uint8 _traitId) external virtual onlyRole(KYC_PROVIDER_ROLE) {
        Metadata storage meta = metas[_account];

        if (meta.traits.get(_traitId)) {
            meta.traits.unset(_traitId);
            emit TraitRemoved(_account, _traitId, block.timestamp);
        }
    }

    function addSanctions(address _account, uint8 _countryId) external virtual onlyRole(KYC_PROVIDER_ROLE) {
        Metadata storage meta = metas[_account];
        if (!meta.sanctions.get(_countryId)) {
            meta.sanctions.set(_countryId);
            meta.sanctionsCount += 1;
            emit SanctionAdded(_account, _countryId, block.timestamp);
        }
    }

    function removeSanction(address _account, uint8 _countryId) external virtual onlyRole(KYC_PROVIDER_ROLE) {
        Metadata storage meta = metas[_account];
        if (meta.sanctions.get(_countryId)) {
            meta.sanctions.unset(_countryId);
            meta.sanctionsCount -= 1;
            emit SanctionRemoved(_account, _countryId, block.timestamp);
        }
    }

    /* ============ View Functions ============ */

    function isKYC(address _account) external view returns (bool) {
        return balanceOf(1) > 0;
    }

    function isSanctionsMonitored(address _account, uint32 _days) public view returns (bool) {
        return mintedAt(_account) >= (block.timestamp - (_days) * 1 days);
    }

    function isSanctionsSafe(address _account) external view returns (bool) {
        return (isSanctionsMonitored(_account) && !metas[_account].sanctionsCount == 0);
    }

    function isSanctionsSafeIn(address _account, uint8 _countryId) external view returns (bool) {
        return (isSanctionsMonitored(_account) && !metas[_account].sanctions.get(_countryId));
    }

    function isCompany(address _account) external view returns (bool) {
        return !metas[tokenId].individual;
    }

    function isIndividual(address _account) external view returns (bool) {
        return metas[_account].individual;
    }

    function mintedAt(address _account) public view returns (uint256) {
        return metas[_account].mintedAt;
    }

    function hasTrait(address _account, string memory trait) external view returns (bool) {
        (bool found, uint256 index) = _allTraits.indexOf(trait);
        return found ? metas[_account].traits.get(index) : false;
    }

    function traits(address _account) external view returns (bool[] memory) {
        BitMapsUpgradeable.BitMap storage tokenTraits = metas[_account].traits;
        // For all possible traits, see if the trait is set in the token, and if so, add
        // the index of the trait to our list of indexes.
        string[] memory result = new bool[](256);
        for (uint256 i = 0; i < 256; i++) {
            result[i] = tokenTraits.get(i);
        }
        return result;
    }

    /* ============ Signature Recovery ============ */

    modifier onlySignerMintTo(
      address _signer,
      address _mintToAddress,
      uint256 _nonce,
      uint256 _id,
      uint256 _expiresAt,
      bytes calldata _signature
    ) {
        require(block.timestamp < _expiresAt, "Signature has expired");
        require(contributors[mintToAddress].nonce == _nonce, "Invalid nonce");

        bytes32 hash = keccak256(
          abi.encodePacked(
            _signer,
            address(this),
            _mintToAddress,
            _id,
            _expiresAt,
            _nonces[mintToAddress],
            block.chainid
          )
        ).toEthSignedMessageHash();

        require(
          hasRole(KYC_PROVIDER_ROLE, msg.sender) &&
          _signer.isValidSignatureNow(hash, _signature),
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

    function supportsInterface(bytes4 interfaceId) public view override(ERC1155Upgradeable, AccessControlUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
