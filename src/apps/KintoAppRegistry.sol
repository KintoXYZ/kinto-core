// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {ERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import {ERC721EnumerableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {KintoWallet} from "@kinto-core/wallet/KintoWallet.sol";
import {IKintoID} from "@kinto-core/interfaces/IKintoID.sol";
import {IKintoAppRegistry} from "@kinto-core/interfaces/IKintoAppRegistry.sol";
import {IKintoWalletFactory} from "@kinto-core/interfaces/IKintoWalletFactory.sol";
import {IKintoWallet} from "@kinto-core/interfaces/IKintoWallet.sol";

/**
 * @title KintoAppRegistry
 * @notice A contract for managing the registration and metadata of KintoApps
 * @dev This contract handles the following main functionalities:
 * 1. Registration of new KintoApps
 * 2. Updating app metadata
 * 3. Managing sponsored contracts
 * 4. Enabling Data Sharing Agreement (DSA) for apps
 * 5. Managing system contracts
 * 6. Controlling access for Externally Owned Accounts (EOAs)
 *
 * The contract uses ERC721 for representing apps as unique tokens and implements
 * upgradeability using the UUPS pattern. It also interacts with KintoID for KYC
 * verification and KintoWalletFactory for wallet-related operations.
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

    /// @notice The default period for rate limiting, set to 1 minute
    uint256 public constant override RATE_LIMIT_PERIOD = 1 minutes;

    /// @notice The default threshold for rate limiting, set to 10 calls
    uint256 public constant override RATE_LIMIT_THRESHOLD = 10;

    /// @notice The default period for gas limiting, set to 30 days
    uint256 public constant override GAS_LIMIT_PERIOD = 30 days;

    /// @notice The default threshold for gas limiting, set to 0.01 ether
    uint256 public constant override GAS_LIMIT_THRESHOLD = 0.01 ether;

    /// @notice The address of the CREATE2 contract
    address public constant CREATE2 = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    /// @notice The KintoWalletFactory contract
    IKintoWalletFactory public immutable override walletFactory;

    /// @notice The KintoID contract
    IKintoID public immutable kintoID;

    /// @notice The address of the admin deployer
    address public constant ADMIN_DEPLOYER = 0x660ad4B5A74130a4796B4d54BC6750Ae93C86e6c;

    /* ============ State Variables ============ */

    /// @notice Mapping of app addresses to their metadata
    mapping(address => IKintoAppRegistry.Metadata) private _appMetadata;

    /// @notice Mapping of child contracts to their parent app contracts
    mapping(address => address) public override childToParentContract;

    /// @notice Mapping of apps to their sponsored contracts
    mapping(address => mapping(address => bool)) private _sponsoredContracts;

    /// @notice Mapping of token IDs to their corresponding app addresses
    mapping(uint256 => address) public override tokenIdToApp;

    /// @notice The total number of registered apps
    uint256 public override appCount;

    /// @notice Mapping of developer EOAs to their associated app addresses
    mapping(address => address) public override devEoaToApp;

    /// @notice Array of system contract addresses
    address[] public override systemContracts;

    /// @notice Mapping to check if an address is a system contract
    mapping(address => bool) public override isSystemContract;

    /// @notice Mapping of deployer EOAs to their associated wallet addresses
    mapping(address => address) public override deployerToWallet;

    /* ============ Events ============ */

    event AppRegistered(address indexed _app, address _owner, uint256 _timestamp);
    event AppUpdated(address indexed _app, address _owner, uint256 _timestamp);
    event AppDSAEnabled(address indexed _app, uint256 _timestamp);
    event SystemContractsUpdated(address[] oldSystemContracts, address[] newSystemContracts);
    event DeployerSet(address indexed newDeployer);

    /* ============ Constructor & Initializers ============ */

    /**
     * @notice Constructs the KintoAppRegistry contract
     * @param _walletFactory The address of the KintoWalletFactory contract
     * @custom:oz-upgrades-unsafe-allow constructor
     */
    constructor(IKintoWalletFactory _walletFactory) {
        _disableInitializers();
        walletFactory = _walletFactory;
        kintoID = IKintoID(_walletFactory.kintoID());
    }

    /// @notice Initializes the contract
    function initialize() external initializer {
        __ERC721_init("Kinto APP", "KINTOAPP");
        __ERC721Enumerable_init();
        __Ownable_init();
        __UUPSUpgradeable_init();
        _transferOwnership(msg.sender);
    }

    /**
     * @notice Authorizes the upgrade of the contract
     * @param newImplementation The address of the new implementation
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /* ============ Token name, symbol & URI ============ */

    /**
     * @notice Gets the token name
     * @return The name of the token
     */
    function name() public pure override(ERC721Upgradeable, IKintoAppRegistry) returns (string memory) {
        return "Kinto APP";
    }

    /**
     * @notice Gets the token symbol
     * @return The symbol of the token
     */
    function symbol() public pure override(ERC721Upgradeable, IKintoAppRegistry) returns (string memory) {
        return "KINTOAPP";
    }

    /**
     * @notice Returns the base token URI
     * @return The base token URI
     */
    function _baseURI() internal pure override returns (string memory) {
        return "https://kinto.xyz/metadata/kintoapp/";
    }

    /* ============ App Registration ============ */

    /**
     * @notice Registers a new app and mints the NFT to the creator
     * @param appName The name of the app
     * @param parentContract The address of the parent contract
     * @param appContracts The addresses of the child contracts
     * @param appLimits The limits of the app
     * @param devEOAs The addresses of the developers EOAs to be whitelisted
     */
    function registerApp(
        string calldata appName,
        address parentContract,
        address[] calldata appContracts,
        uint256[4] calldata appLimits,
        address[] calldata devEOAs
    ) external override {
        if (!kintoID.isKYC(msg.sender)) revert KYCRequired();
        if (_appMetadata[parentContract].tokenId != 0) revert AlreadyRegistered();
        if (childToParentContract[parentContract] != address(0)) revert ParentAlreadyChild();
        if (walletFactory.walletTs(parentContract) != 0) revert CannotRegisterWallet();

        appCount++;
        _updateMetadata(appCount, appName, parentContract, appContracts, appLimits, devEOAs);
        _safeMint(msg.sender, appCount);

        emit AppRegistered(parentContract, msg.sender, block.timestamp);
    }

    /**
     * @notice Allows the developer to update the metadata of the app
     * @param appName The name of the app
     * @param parentContract The address of the parent contract
     * @param appContracts The addresses of the child contracts
     * @param appLimits The limits of the app
     * @param devEOAs The addresses of the developers EOAs to be whitelisted
     */
    function updateMetadata(
        string calldata appName,
        address parentContract,
        address[] calldata appContracts,
        uint256[4] calldata appLimits,
        address[] calldata devEOAs
    ) external override {
        uint256 tokenId = _appMetadata[parentContract].tokenId;
        if (msg.sender != ownerOf(tokenId)) revert OnlyAppDeveloper();
        _updateMetadata(tokenId, appName, parentContract, appContracts, appLimits, devEOAs);

        emit AppUpdated(parentContract, msg.sender, block.timestamp);
    }

    /**
     * @notice Allows the developer to set sponsored contracts
     * @param _app The address of the app
     * @param _contracts The addresses of the contracts
     * @param _flags The flags of the contracts
     */
    function setSponsoredContracts(address _app, address[] calldata _contracts, bool[] calldata _flags)
        external
        override
    {
        if (_contracts.length != _flags.length) revert LengthMismatch();
        if (
            _appMetadata[_app].tokenId == 0
                || (msg.sender != ownerOf(_appMetadata[_app].tokenId) && msg.sender != owner())
        ) {
            revert InvalidSponsorSetter();
        }
        for (uint256 i = 0; i < _contracts.length; i++) {
            _sponsoredContracts[_app][_contracts[i]] = _flags[i];
        }
    }

    /**
     * @notice Allows the app to request PII data
     * @param app The address of the app
     */
    function enableDSA(address app) external override onlyOwner {
        if (_appMetadata[app].dsaEnabled) revert DSAAlreadyEnabled();
        _appMetadata[app].dsaEnabled = true;
        emit AppDSAEnabled(app, block.timestamp);
    }

    /**
     * @notice Allows the owner to override the parent contract of a child contract
     * @param child The address of the child contract
     * @param parent The address of the parent contract
     */
    function overrideChildToParentContract(address child, address parent) external override onlyOwner {
        childToParentContract[child] = parent;
    }

    /**
     * @notice Updates the system contracts array
     * @param newSystemContracts The new array of system contracts
     */
    function updateSystemContracts(address[] calldata newSystemContracts) external onlyOwner {
        emit SystemContractsUpdated(systemContracts, newSystemContracts);
        for (uint256 index = 0; index < systemContracts.length; index++) {
            isSystemContract[systemContracts[index]] = false;
        }
        for (uint256 index = 0; index < newSystemContracts.length; index++) {
            isSystemContract[newSystemContracts[index]] = true;
        }
        systemContracts = newSystemContracts;
    }

    /**
     * @notice Sets the deployer EOA for a wallet
     * @param deployer The address of the deployer EOA
     */
    function setDeployerEOA(address deployer) external {
        address wallet = msg.sender;
        if (walletFactory.walletTs(wallet) == 0) revert InvalidWallet(msg.sender);

        emit DeployerSet(deployer);
        deployerToWallet[deployer] = wallet;
    }

    /* ============ Getters ============ */

    /**
     * @notice Returns whether the contract implements the interface defined by the id
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

    /**
     * @notice Returns the metadata of the app
     * @param _contract The address of the app
     * @return The metadata of the app
     */
    function getAppMetadata(address _contract) external view override returns (IKintoAppRegistry.Metadata memory) {
        return
            _appMetadata[childToParentContract[_contract] != address(0) ? childToParentContract[_contract] : _contract];
    }

    /**
     * @notice Returns the limits of the app
     * @param _contract The address of the app
     * @return The limits of the app
     */
    function getContractLimits(address _contract) external view override returns (uint256[4] memory) {
        IKintoAppRegistry.Metadata memory metadata =
            _appMetadata[childToParentContract[_contract] != address(0) ? childToParentContract[_contract] : _contract];
        return [
            metadata.rateLimitPeriod != 0 ? metadata.rateLimitPeriod : RATE_LIMIT_PERIOD,
            metadata.rateLimitNumber != 0 ? metadata.rateLimitNumber : RATE_LIMIT_THRESHOLD,
            metadata.gasLimitPeriod != 0 ? metadata.gasLimitPeriod : GAS_LIMIT_PERIOD,
            metadata.gasLimitCost != 0 ? metadata.gasLimitCost : GAS_LIMIT_THRESHOLD
        ];
    }

    /**
     * @notice Returns whether a contract is sponsored by an app
     * @param _app The address of the app
     * @param _contract The address of the contract
     * @return bool true or false
     */
    function isSponsored(address _app, address _contract) external view override returns (bool) {
        return _contract == _app || childToParentContract[_contract] == _app || _sponsoredContracts[_app][_contract];
    }

    /**
     * @notice Returns the sponsoring contract for a given contract (aka parent contract)
     * @param _contract The address of the contract
     * @return The address of the contract that sponsors the contract
     */
    function getSponsor(address _contract) external view override returns (address) {
        address sponsor = childToParentContract[_contract];
        if (sponsor != address(0)) return sponsor;
        return _contract;
    }

    /**
     * @notice Determines if a contract call is allowed from an EOA (Externally Owned Account)
     * @dev This function checks various conditions to decide if an EOA can call a specific contract:
     *      1. Allows calls to system contracts from any EOA
     *      2. Checks if the EOA has a linked wallet
     *      3. Verifies if dev mode is enabled on the wallet
     *      4. Ensures the wallet owner has completed KYC
     *      5. Permits CREATE and CREATE2 operations for eligible EOAs
     *      6. Allows dev EOAs to call their respective apps
     * @param from The address of the EOA initiating the call
     * @param to The address of the contract being called
     * @return A boolean indicating whether the contract call is allowed (true) or not (false)
     */
    function isContractCallAllowedFromEOA(address from, address to) external view returns (bool) {
        // Calls to system contracts are allwed for any EOA
        if (isSystemContract[to]) return true;

        // Deployer EOAs are allowed to use CREATE and CREATE2
        if (to == address(0) || to == CREATE2) {
            address wallet = deployerToWallet[from];
            // Only dev wallets can deploy
            if (wallet == address(0)) return false;
            // Deny if wallet has no KYC
            if (!kintoID.isKYC(IKintoWallet(wallet).owners(0))) return false;
            // Permit if EOA have a wallet, dev mode and KYC
            return true;
        }

        // Contract calls are allowed only from dev EOAs to app's contracts
        address app = childToParentContract[to] != address(0) ? childToParentContract[to] : to;

        // Dev EOAs are allowed to call their respective apps
        if (devEoaToApp[from] == app) {
            // Deny if wallet has no KYC
            if (!kintoID.isKYC(ownerOf(_appMetadata[app].tokenId))) return false;
            return true;
        }

        return false;
    }

    /* =========== Internal methods =========== */

    /**
     * @notice Updates the metadata of an app
     * @param tokenId The token ID of the app
     * @param appName The name of the app
     * @param parentContract The address of the parent contract
     * @param appContracts The addresses of the child contracts
     * @param appLimits The limits of the app
     * @param devEOAs The addresses of the developers EOAs to be whitelisted
     */
    function _updateMetadata(
        uint256 tokenId,
        string calldata appName,
        address parentContract,
        address[] calldata appContracts,
        uint256[4] calldata appLimits,
        address[] calldata devEOAs
    ) internal {
        // Cleanup old devEOAs
        address[] memory oldArray = _appMetadata[parentContract].devEOAs;
        for (uint256 i = 0; i < oldArray.length; i++) {
            devEoaToApp[oldArray[i]] = address(0);
        }

        // Cleanup old appContracts
        oldArray = _appMetadata[parentContract].appContracts;
        for (uint256 i = 0; i < oldArray.length; i++) {
            childToParentContract[oldArray[i]] = address(0);
        }

        IKintoAppRegistry.Metadata memory metadata = IKintoAppRegistry.Metadata({
            tokenId: tokenId,
            name: appName,
            dsaEnabled: false,
            rateLimitPeriod: appLimits[0],
            rateLimitNumber: appLimits[1],
            gasLimitPeriod: appLimits[2],
            gasLimitCost: appLimits[3],
            devEOAs: devEOAs,
            appContracts: appContracts
        });

        tokenIdToApp[tokenId] = parentContract;
        _appMetadata[parentContract] = metadata;

        // Sets Child to parent contract
        for (uint256 i = 0; i < appContracts.length; i++) {
            if (walletFactory.walletTs(appContracts[i]) > 0) revert CannotRegisterWallet();
            if (childToParentContract[appContracts[i]] != address(0)) revert ChildAlreadyRegistered();
            childToParentContract[appContracts[i]] = parentContract;
        }

        for (uint256 i = 0; i < devEOAs.length; i++) {
            devEoaToApp[devEOAs[i]] = parentContract;
        }
    }

    /**
     * @notice Hook that is called before any token transfer. Allow only mints and burns, no transfers
     * @param from source address
     * @param to target address
     * @param batchSize The first id
     */
    function _beforeTokenTransfer(address from, address to, uint256 firstTokenId, uint256 batchSize)
        internal
        virtual
        override(ERC721Upgradeable, ERC721EnumerableUpgradeable)
    {
        if ((from != address(0) && from != ADMIN_DEPLOYER && from != owner()) || to == address(0)) {
            revert OnlyMintingAllowed();
        }
        super._beforeTokenTransfer(from, to, firstTokenId, batchSize);
    }
}

contract KintoAppRegistryV7 is KintoAppRegistry {
    constructor(IKintoWalletFactory _walletFactory) KintoAppRegistry(_walletFactory) {}
}
