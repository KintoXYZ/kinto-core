// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import "../interfaces/IKintoID.sol";
import "../interfaces/IKintoApp.sol";
import "../interfaces/IKintoWalletFactory.sol";

// import "forge-std/console2.sol";

/**
 * @title KintoApp
 * @dev A contract that holds all the information of a KintoApp
 */
contract KintoApp is
    Initializable,
    ERC721Upgradeable,
    ERC721EnumerableUpgradeable,
    ERC721BurnableUpgradeable,
    AccessControlUpgradeable,
    UUPSUpgradeable,
    IKintoApp
{

    /* ============ Constants ============ */
    bytes32 public constant override UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant override DEVELOPER_ADMIN = keccak256("DEVELOPER_ADMIN");
    
    /* ============ State Variables ============ */

    uint256 private _nextTokenId;

    mapping (address => IKintoApp.Metadata) public appMetadata;
    mapping (address => address) public childToParentContract;

    /* ============ Events ============ */

    /* ============ Constructor & Initializers ============ */

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() external initializer {
        __ERC721_init("Kinto APP", "KINTOAPP");
        __ERC721Enumerable_init();
        __ERC721Burnable_init();
        __AccessControl_init();
        __UUPSUpgradeable_init();
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(UPGRADER_ROLE, msg.sender);
        _grantRole(DEVELOPER_ADMIN, msg.sender);
    }

    /**
     * @dev Authorize the upgrade. Only by the upgrader role.
     * @param newImplementation address of the new implementation
     */
    // This function is called by the proxy contract when the implementation is upgraded
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}

    /* ============ App Registration ============ */

    /**
     * @dev Register a new app and mints the NFT to the creator
     * @param _name The name of the app
     * @param parentContract The address of the parent contract
     * @param childContracts The addresses of the child contracts
     * @param appLimits The limits of the app
     */
    function registerApp(string calldata _name, address parentContract, address[] calldata childContracts, uint256[4] calldata appLimits) external override {
        require(appLimits.length == 4, "Invalid app limits");
        IKintoApp.Metadata memory metadata = IKintoApp.Metadata({
            name: _name,
            developerWallet: msg.sender, 
            dsaEnabled: false,
            rateLimitPeriod: appLimits[0],
            rateLimitNumber: appLimits[1],
            gasLimitPeriod: appLimits[2],
            gasLimitCost: appLimits[3]
        });
        appMetadata[parentContract] = metadata;
        for (uint256 i = 0; i < childContracts.length; i++) {
            childToParentContract[childContracts[i]] = parentContract;
        }
        _nextTokenId++;
        _safeMint(msg.sender, _nextTokenId);
    }

    /**
     * @dev Allows the app to request PII data
     * @param app The name of the app
     */
    function enableDSA(address app) external override onlyRole(DEVELOPER_ADMIN) {
        require(appMetadata[app].dsaEnabled == false, "DSA already enabled");
        appMetadata[app].dsaEnabled = true;
    }

    /* ============ App Info Fetching ============ */

    /**
     * @dev Returns the metadata of the app
     * @param _contract The address of the app
     * @return The metadata of the app
     */
    function getAppMetadata(address _contract) external view override returns (IKintoApp.Metadata memory) {
        address finalContract = childToParentContract[_contract] != address(0) ? childToParentContract[_contract] : _contract;
        return appMetadata[finalContract];
    }

    /**
     * @dev Returns the limits of the app
     * @param _contract The address of the app
     * @return The limits of the app
     */
    function getContractLimits(address _contract) external view override returns (uint256[4] memory) {
        address finalContract = childToParentContract[_contract] != address(0) ? childToParentContract[_contract] : _contract;
        IKintoApp.Metadata memory metadata = appMetadata[finalContract];
        return [metadata.rateLimitPeriod, metadata.rateLimitNumber, metadata.gasLimitPeriod, metadata.gasLimitCost];
    }

    /* ============ Token name, symbol & URI ============ */

    /**
     * @dev Gets the token name.
     * @return string representing the token name
     */
    function name() public pure override(ERC721Upgradeable, IKintoApp) returns (string memory) {
        return "Kinto APP";
    }

    /**
     * @dev Gets the token symbol.
     * @return string representing the token symbol
     */
    function symbol() public pure override(ERC721Upgradeable, IKintoApp) returns (string memory) {
        return "KINTOAPP";
    }

    /**
     * @dev Returns the base token URI. ID is appended
     * @return token URI.
     */
    function _baseURI() internal pure override returns (string memory) {
        return "https://kinto.xyz/metadata/kintoapp/";
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
        require(
            (from == address(0) && to != address(0)) || (from != address(0) && to == address(0)),
            "Only mint or burn transfers are allowed"
        );
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
