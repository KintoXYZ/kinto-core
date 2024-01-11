// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import "../interfaces/IKintoID.sol";
import "../interfaces/IKintoAppRegistry.sol";
import "../interfaces/IKintoWalletFactory.sol";

/**
 * @title KintoAppRegistry
 * @dev A contract that holds all the information of a KintoApp
 */
contract KintoAppRegistry is
    Initializable,
    ERC721Upgradeable,
    ERC721EnumerableUpgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable,
    IKintoAppRegistry
{
    /* ============ Constants ============ */
    uint256 public constant override RATE_LIMIT_PERIOD = 1 minutes;
    uint256 public constant override RATE_LIMIT_THRESHOLD = 10;
    uint256 public constant override GAS_LIMIT_PERIOD = 30 days;
    uint256 public constant override GAS_LIMIT_THRESHOLD = 1e16; // 0.01 ETH

    /* ============ State Variables ============ */
    IKintoWalletFactory public immutable override walletFactory;
    mapping(address => IKintoAppRegistry.Metadata) private _appMetadata;
    // other contracts to be sponsored that dont belong in the app
    mapping(address => mapping(address => bool)) private _sponsoredContracts;
    // Mapping between the app and all the contracts that belong to it
    mapping(address => address) public override childToParentContract;
    // Mapping between token id and app metadata
    mapping(uint256 => address) public override tokenIdToApp;
    uint256 public override appCount;

    /* ============ Events ============ */
    event AppCreated(address indexed _app, address _owner, uint256 _timestamp);
    event AppUpdated(address indexed _app, address _owner, uint256 _timestamp);
    event AppDSAEnabled(address indexed _app, uint256 _timestamp);

    /* ============ Constructor & Initializers ============ */

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(IKintoWalletFactory _walletFactory) {
        _disableInitializers();
        walletFactory = _walletFactory;
    }

    function initialize() external initializer {
        __ERC721_init("Kinto APP", "KINTOAPP");
        __ERC721Enumerable_init();
        __Ownable_init();
        __UUPSUpgradeable_init();
        _transferOwnership(msg.sender);
    }

    /**
     * @dev Authorize the upgrade. Only by the upgrader role.
     * @param newImplementation address of the new implementation
     */
    // This function is called by the proxy contract when the implementation is upgraded
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /* ============ Token name, symbol & URI ============ */

    /**
     * @dev Gets the token name.
     * @return string representing the token name
     */
    function name() public pure override(ERC721Upgradeable, IKintoAppRegistry) returns (string memory) {
        return "Kinto APP";
    }

    /**
     * @dev Gets the token symbol.
     * @return string representing the token symbol
     */
    function symbol() public pure override(ERC721Upgradeable, IKintoAppRegistry) returns (string memory) {
        return "KINTOAPP";
    }

    /**
     * @dev Returns the base token URI. ID is appended
     * @return token URI.
     */
    function _baseURI() internal pure override returns (string memory) {
        return "https://kinto.xyz/metadata/kintoapp/";
    }

    /* ============ App Registration ============ */

    /**
     * @dev Register a new app and mints the NFT to the creator
     * @param _name The name of the app
     * @param parentContract The address of the parent contract
     * @param appContracts The addresses of the child contracts
     * @param appLimits The limits of the app
     */
    function registerApp(
        string calldata _name,
        address parentContract,
        address[] calldata appContracts,
        uint256[4] calldata appLimits
    ) external override {
        require(_appMetadata[parentContract].tokenId == 0, "App already registered");
        require(childToParentContract[parentContract] == address(0), "Parent contract already registered as a child");
        appCount++;
        _updateMetadata(appCount, _name, parentContract, appContracts, appLimits);
        _safeMint(msg.sender, appCount);
        emit AppCreated(parentContract, msg.sender, block.timestamp);
    }

    /**
     * @dev Allows the developer to set sponsored contracts
     * @param _app The address of the app
     * @param _contracts The addresses of the contracts
     * @param _flags The flags of the contracts
     */
    function setSponsoredContracts(address _app, address[] calldata _contracts, bool[] calldata _flags)
        external
        override
    {
        require(_contracts.length == _flags.length, "Invalid input");
        require(
            _appMetadata[_app].tokenId > 0 && msg.sender == ownerOf(_appMetadata[_app].tokenId),
            "Only developer can set sponsored contracts"
        );
        for (uint256 i = 0; i < _contracts.length; i++) {
            _sponsoredContracts[_app][_contracts[i]] = _flags[i];
        }
    }

    /**
     * @dev Allows the developer to update the metadata of the app
     * @param _name The name of the app
     * @param parentContract The address of the parent contract
     * @param appContracts The addresses of the child contracts
     * @param appLimits The limits of the app
     */
    function updateMetadata(
        string calldata _name,
        address parentContract,
        address[] calldata appContracts,
        uint256[4] calldata appLimits
    ) external override {
        uint256 tokenId = _appMetadata[parentContract].tokenId;
        require(msg.sender == ownerOf(tokenId), "Only developer can update metadata");
        _updateMetadata(tokenId, _name, parentContract, appContracts, appLimits);
        emit AppUpdated(parentContract, msg.sender, block.timestamp);
    }

    /**
     * @dev Allows the app to request PII data
     * @param app The name of the app
     */
    function enableDSA(address app) external override onlyOwner {
        require(_appMetadata[app].dsaEnabled == false, "DSA already enabled");
        _appMetadata[app].dsaEnabled = true;
        emit AppDSAEnabled(app, block.timestamp);
    }

    /* ============ App Info Fetching ============ */

    /**
     * @dev Returns the metadata of the app
     * @param _contract The address of the app
     * @return The metadata of the app
     */
    function getAppMetadata(address _contract) external view override returns (IKintoAppRegistry.Metadata memory) {
        address mainContract =
            childToParentContract[_contract] != address(0) ? childToParentContract[_contract] : _contract;
        return _appMetadata[mainContract];
    }

    /**
     * @dev Returns the limits of the app
     * @param _contract The address of the app
     * @return The limits of the app
     */
    function getContractLimits(address _contract) external view override returns (uint256[4] memory) {
        address mainContract =
            childToParentContract[_contract] != address(0) ? childToParentContract[_contract] : _contract;
        IKintoAppRegistry.Metadata memory metadata = _appMetadata[mainContract];
        return [
            metadata.rateLimitPeriod != 0 ? metadata.rateLimitPeriod : RATE_LIMIT_PERIOD,
            metadata.rateLimitNumber != 0 ? metadata.rateLimitNumber : RATE_LIMIT_THRESHOLD,
            metadata.gasLimitPeriod != 0 ? metadata.gasLimitPeriod : GAS_LIMIT_PERIOD,
            metadata.gasLimitCost != 0 ? metadata.gasLimitCost : GAS_LIMIT_THRESHOLD
        ];
    }

    /**
     * @dev Returns whether a contract is sponsored by an app
     * @param _app The address of the app
     * @param _contract The address of the contract
     * @return bool true or false
     */
    function isContractSponsored(address _app, address _contract) external view override returns (bool) {
        return _contract == _app || childToParentContract[_contract] == _app || _sponsoredContracts[_app][_contract];
    }

    /**
     * @dev Returns the sponsoring contract
     * @param _contract The address of the contract
     * @return The address of the contract that sponsors the contract
     */
    function getSponsor(address _contract) external view override returns (address) {
        if (childToParentContract[_contract] != address(0)) {
            return childToParentContract[_contract];
        }
        return _contract;
    }

    /* =========== App metadata params =========== */
    function _updateMetadata(
        uint256 tokenId,
        string calldata _name,
        address parentContract,
        address[] calldata appContracts,
        uint256[4] calldata appLimits
    ) internal {
        IKintoAppRegistry.Metadata memory metadata = IKintoAppRegistry.Metadata({
            tokenId: tokenId,
            name: _name,
            dsaEnabled: false,
            rateLimitPeriod: appLimits[0],
            rateLimitNumber: appLimits[1],
            gasLimitPeriod: appLimits[2],
            gasLimitCost: appLimits[3]
        });
        tokenIdToApp[tokenId] = parentContract;
        _appMetadata[parentContract] = metadata;
        for (uint256 i = 0; i < appContracts.length; i++) {
            childToParentContract[appContracts[i]] = parentContract;
        }
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
        require((from == address(0) && to != address(0)), "Only mint transfers are allowed");
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
        override(ERC721Upgradeable, ERC721EnumerableUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
