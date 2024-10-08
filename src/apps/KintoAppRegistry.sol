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
import {SponsorPaymaster} from "@kinto-core/paymasters/SponsorPaymaster.sol";

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

    /// @notice The SponsorPaymaster contract
    SponsorPaymaster public immutable paymaster;

    /// @notice The KintoWalletFactory contract
    IKintoWalletFactory public immutable override walletFactory;

    /// @notice The KintoID contract
    IKintoID public immutable kintoID;

    /// @notice The address of the admin deployer
    address public constant ADMIN_DEPLOYER = 0x660ad4B5A74130a4796B4d54BC6750Ae93C86e6c;

    /// @notice
    address public constant ENTRYPOINT_V6 = 0x2843C269D2a64eCfA63548E8B3Fc0FD23B7F70cb;

    /// @notice
    address public constant ENTRYPOINT_V7 = 0x0000000071727De22E5E9d8BAf0edAc6f37da032;

    /// @notice
    address public constant ARB_RETRAYABLE_TX = 0x000000000000000000000000000000000000006E;

    bytes4 public constant SELECTOR_EP_WITHDRAW_STAKE = 0xc23a5cea;
    bytes4 public constant SELECTOR_EP_WITHDRAW_TO = 0x205c2878;
    bytes4 public constant SELECTOR_EP_HANDLEOPS = 0x1fad948c;
    bytes4 public constant SELECTOR_EP_HANDLE_OPS_V7 = 0x765e827f;
    bytes4 public constant SELECTOR_SP_WITHDRAW_TO = 0x205c2878;
    bytes4 public constant SELECTOR_SP_DEPOSIT = 0xd0e30db0;
    bytes4 public constant SELECTOR_EP_DEPOSIT = 0xb760faf9;
    bytes4 public constant SELECTOR_EMPTY = 0x00000000;

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

    /// @notice Mapping of wallet addresses to their associated deployer EOAs
    mapping(address => address) public override walletToDeployer;

    /// @notice Array of reserved contract addresses
    address[] public override reservedContracts;

    /// @notice Mapping to check if an address is a reserved contract
    mapping(address => bool) public override isReservedContract;

    /// @notice Array of system app addresses
    address[] public override systemApps;

    /// @notice Mapping to check if an address is a app contract
    mapping(address => bool) public override isSystemApp;

    /* ============ Constructor & Initializers ============ */

    /**
     * @notice Constructs the KintoAppRegistry contract
     * @param _walletFactory The address of the KintoWalletFactory contract
     */
    constructor(IKintoWalletFactory _walletFactory, SponsorPaymaster _paymaster) {
        _disableInitializers();
        walletFactory = _walletFactory;
        paymaster = _paymaster;
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

    /// @inheritdoc IKintoAppRegistry
    function name() public pure override(ERC721Upgradeable, IKintoAppRegistry) returns (string memory) {
        return "Kinto APP";
    }

    /// @inheritdoc IKintoAppRegistry
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

    /// @inheritdoc IKintoAppRegistry
    function registerApp(
        string calldata appName,
        address parentContract,
        address[] calldata appContracts,
        uint256[4] calldata appLimits,
        address[] calldata devEOAs
    ) external override {
        if (walletFactory.walletTs(msg.sender) == 0) revert InvalidWallet(msg.sender);
        if (!kintoID.isKYC(IKintoWallet(msg.sender).owners(0))) revert KYCRequired();
        if (_appMetadata[parentContract].tokenId != 0) revert AlreadyRegistered(parentContract);
        if (childToParentContract[parentContract] != address(0)) revert ParentAlreadyChild(parentContract);
        if (walletFactory.walletTs(parentContract) != 0) revert CannotRegisterWallet(parentContract);

        appCount++;
        _updateMetadata(appCount, appName, parentContract, appContracts, appLimits, devEOAs);
        _safeMint(msg.sender, appCount);

        emit AppRegistered(parentContract, msg.sender, block.timestamp);
    }

    /// @inheritdoc IKintoAppRegistry
    function updateMetadata(
        string calldata appName,
        address parentContract,
        address[] calldata appContracts,
        uint256[4] calldata appLimits,
        address[] calldata devEOAs
    ) external override {
        uint256 tokenId = _appMetadata[parentContract].tokenId;
        if (msg.sender != ownerOf(tokenId)) revert OnlyAppDeveloper(msg.sender, ownerOf(tokenId));
        _updateMetadata(tokenId, appName, parentContract, appContracts, appLimits, devEOAs);

        emit AppUpdated(parentContract, msg.sender, block.timestamp);
    }

    /// @inheritdoc IKintoAppRegistry
    function setSponsoredContracts(address app, address[] calldata targets, bool[] calldata flags) external override {
        if (targets.length != flags.length) revert LengthMismatch(targets.length, flags.length);
        if (
            _appMetadata[app].tokenId == 0
                || (msg.sender != ownerOf(_appMetadata[app].tokenId) && msg.sender != owner())
        ) {
            revert InvalidSponsorSetter(msg.sender, ownerOf(_appMetadata[app].tokenId));
        }
        for (uint256 i = 0; i < targets.length; i++) {
            if (targets[i].code.length == 0) revert ContractHasNoBytecode(targets[i]);
            _sponsoredContracts[app][targets[i]] = flags[i];
        }
    }

    /// @inheritdoc IKintoAppRegistry
    function enableDSA(address app) external override onlyOwner {
        if (_appMetadata[app].dsaEnabled) revert DSAAlreadyEnabled(app);
        _appMetadata[app].dsaEnabled = true;
        emit AppDSAEnabled(app, block.timestamp);
    }

    /// @inheritdoc IKintoAppRegistry
    function overrideChildToParentContract(address child, address parent) external override onlyOwner {
        childToParentContract[child] = parent;
    }

    /// @inheritdoc IKintoAppRegistry
    function updateSystemApps(address[] calldata newSystemApps) external onlyOwner {
        emit SystemAppsUpdated(systemApps, newSystemApps);
        for (uint256 index = 0; index < systemApps.length; index++) {
            isSystemApp[systemApps[index]] = false;
        }
        for (uint256 index = 0; index < newSystemApps.length; index++) {
            isSystemApp[newSystemApps[index]] = true;
        }
        systemApps = newSystemApps;
    }

    /// @inheritdoc IKintoAppRegistry
    function updateSystemContracts(address[] calldata newSystemContracts) external onlyOwner {
        address[] memory newSystemContractsExtra = new address[](newSystemContracts.length + 4);
        newSystemContractsExtra[0] = address(this);
        newSystemContractsExtra[1] = ENTRYPOINT_V6;
        newSystemContractsExtra[2] = ENTRYPOINT_V7;
        newSystemContractsExtra[3] = ARB_RETRAYABLE_TX;
        for (uint256 i = 0; i < newSystemContracts.length; i++) {
            newSystemContractsExtra[i + 4] = newSystemContracts[i];
        }
        emit SystemContractsUpdated(systemContracts, newSystemContractsExtra);
        for (uint256 index = 0; index < systemContracts.length; index++) {
            isSystemContract[systemContracts[index]] = false;
        }
        for (uint256 index = 0; index < newSystemContractsExtra.length; index++) {
            isSystemContract[newSystemContractsExtra[index]] = true;
        }
        systemContracts = newSystemContractsExtra;
    }

    /// @inheritdoc IKintoAppRegistry
    function updateReservedContracts(address[] calldata newReservedContracts) external onlyOwner {
        emit ReservedContractsUpdated(reservedContracts, newReservedContracts);
        for (uint256 index = 0; index < reservedContracts.length; index++) {
            isReservedContract[reservedContracts[index]] = false;
        }
        for (uint256 index = 0; index < newReservedContracts.length; index++) {
            isReservedContract[newReservedContracts[index]] = true;
        }
        reservedContracts = newReservedContracts;
    }

    /// @inheritdoc IKintoAppRegistry
    function setDeployerEOA(address wallet, address deployer) external {
        if (walletFactory.walletTs(wallet) == 0) revert InvalidWallet(wallet);
        if (msg.sender != owner() && msg.sender != wallet) revert InvalidWallet(wallet);

        // cleanup old
        if (walletToDeployer[wallet] != address(0)) {
            delete deployerToWallet[walletToDeployer[wallet]];
            delete walletToDeployer[wallet];
        }

        emit DeployerSet(deployer);
        walletToDeployer[wallet] = deployer;
        deployerToWallet[deployer] = wallet;
    }

    /* ============ Getters ============ */

    /// @dev See {IERC165-supportsInterface}.
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721Upgradeable, ERC721EnumerableUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    /// @inheritdoc IKintoAppRegistry
    function getAppMetadata(address target) external view override returns (IKintoAppRegistry.Metadata memory) {
        return _appMetadata[childToParentContract[target] != address(0) ? childToParentContract[target] : target];
    }

    /// @inheritdoc IKintoAppRegistry
    function getContractLimits(address target) external view override returns (uint256[4] memory limits) {
        address app = childToParentContract[target] != address(0) ? childToParentContract[target] : target;

        uint256 rateLimitPeriod = _appMetadata[app].rateLimitPeriod;
        uint256 rateLimitNumber = _appMetadata[app].rateLimitNumber;
        uint256 gasLimitPeriod = _appMetadata[app].gasLimitPeriod;
        uint256 gasLimitCost = _appMetadata[app].gasLimitCost;

        // Assign values to the return array
        limits[0] = rateLimitPeriod != 0 ? rateLimitPeriod : RATE_LIMIT_PERIOD;
        limits[1] = rateLimitNumber != 0 ? rateLimitNumber : RATE_LIMIT_THRESHOLD;
        limits[2] = gasLimitPeriod != 0 ? gasLimitPeriod : GAS_LIMIT_PERIOD;
        limits[3] = gasLimitCost != 0 ? gasLimitCost : GAS_LIMIT_THRESHOLD;
    }

    /// @inheritdoc IKintoAppRegistry
    function isSponsored(address app, address target) external view override returns (bool) {
        return target == app || childToParentContract[target] == app || _sponsoredContracts[app][target];
    }

    /// @inheritdoc IKintoAppRegistry
    function getApp(address target) public view override returns (address) {
        return childToParentContract[target] != address(0) ? childToParentContract[target] : target;
    }

    function isEntryPoint(address addr) public pure returns (bool) {
        return addr == ENTRYPOINT_V6 || addr == ENTRYPOINT_V7;
    }

    function isEntryPointWithdraw(bytes4 selector) public pure returns (bool) {
        return selector == SELECTOR_EP_WITHDRAW_TO || selector == SELECTOR_EP_WITHDRAW_STAKE;
    }

    function isHandleOps(address addr, bytes4 selector) public pure returns (bool) {
        return isEntryPoint(addr) && (selector == SELECTOR_EP_HANDLEOPS || selector == SELECTOR_EP_HANDLE_OPS_V7);
    }

    function forbiddenEPFunctions(bytes4 selector) public pure returns (bool) {
        return selector == SELECTOR_EMPTY || selector == SELECTOR_EP_DEPOSIT;
    }

    function paymasterFunctionNotAllowed(bytes4 selector) public pure returns (bool) {
        return selector == SELECTOR_SP_WITHDRAW_TO || selector == SELECTOR_SP_DEPOSIT;
    }

    /**
     * @dev This function checks various conditions to decide if an EOA can call a specific contract:
     *      1. Allows calls to system contracts from any EOA
     *      2. Checks if the EOA has a linked wallet
     *      3. Verifies if dev mode is enabled on the wallet
     *      4. Ensures the wallet owner has completed KYC
     *      5. Permits CREATE and CREATE2 operations for eligible EOAs
     *      6. Allows dev EOAs to call their respective apps
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
        address app = childToParentContract[to] != address(0)
            ? childToParentContract[to]
            : devEoaToApp[to] != address(0) ? devEoaToApp[to] : to;

        // Dev EOAs are allowed to call their respective apps
        // Dev EOAs can send ETH to each other
        if (devEoaToApp[from] == app || (devEoaToApp[from] == devEoaToApp[to] && devEoaToApp[from] != address(0))) {
            // Deny if wallet has no KYC
            address walletOwner = ownerOf(_appMetadata[app].tokenId);
            // App owner must be a wallet
            if (walletFactory.walletTs(walletOwner) == 0) return false;
            if (!kintoID.isKYC(IKintoWallet(walletOwner).owners(0))) return false;
            return true;
        }

        return false;
    }

    /**
     * @inheritdoc IKintoAppRegistry
     * @dev This function checks various conditions to decide if an EOA can call a specific contract:
     *      1. Allows calls to system contracts from any EOA
     *      2. Checks if the EOA has a linked wallet
     *      3. Verifies if dev mode is enabled on the wallet
     *      4. Ensures the wallet owner has completed KYC
     *      5. Permits CREATE and CREATE2 operations for eligible EOAs
     *      6. Allows dev EOAs to call their respective apps
     */
    function isContractCallAllowedFromEOA(address sender, address destination, bytes calldata callData, uint256 value)
        external
        view
        returns (bool)
    {
        (value);
        // extract the function selector from the callData
        bytes4 selector = callData.length > 0 ? bytes4(callData[:4]) : bytes4(0);

        if (isEntryPoint(destination) && isEntryPointWithdraw(selector)) {
            // function withdrawStake(address payable withdrawAddress) external;
            // function withdrawTo(address payable withdrawAddress, uint256 withdrawAmount) external;
            address paramAddress = abi.decode(callData[4:36], (address));

            if (sender != paramAddress) {
                // Trying to withdrawTo/withdrawStake from EntryPoint to a param different than the sender
                return false;
            }
        }

        if (isHandleOps(destination, selector)) {
            // function handleOps(PackedUserOperation[] calldata ops, address payable beneficiary) external;
            (, address beneficiary) = abi.decode(callData[4:], (bytes32, address));

            if (sender != beneficiary) {
                // Trying to handleOps from EntryPoint to a beneficiary different than the sender
                return false;
            }
        }

        if (isEntryPoint(destination) && forbiddenEPFunctions(selector)) {
            // EntryPoint depositTo, HandleAggregatedOps and fallback functions are not allowed
            return false;
        }

        if (destination == address(paymaster) && paymasterFunctionNotAllowed(selector)) {
            // SponsorPaymaster withDrawTo() and deposit() are not allowed
            return false;
        }

        // Calls to system contracts are allowed for any EOA
        if (isSystemContract[destination]) return true;

        // Deployer EOAs are allowed to use CREATE and CREATE2
        if (destination == address(0) || destination == CREATE2) {
            address wallet = deployerToWallet[sender];
            // Only dev wallets can deploy
            if (wallet == address(0)) return false;
            // Deny if wallet has no KYC
            if (!kintoID.isKYC(IKintoWallet(wallet).owners(0))) return false;
            // Permit if EOA have a wallet, dev mode and KYC
            return true;
        }

        // Contract calls are allowed only sender dev EOAs to app's contracts
        address app = childToParentContract[destination] != address(0)
            ? childToParentContract[destination]
            : devEoaToApp[destination] != address(0) ? devEoaToApp[destination] : destination;

        // Dev EOAs are allowed to call their respective apps
        // Dev EOAs can send ETH to each other
        if (
            devEoaToApp[sender] == app
                || (devEoaToApp[sender] == devEoaToApp[destination] && devEoaToApp[sender] != address(0))
        ) {
            // Deny if wallet has no KYC
            address walletOwner = ownerOf(_appMetadata[app].tokenId);
            // App owner must be a wallet
            if (walletFactory.walletTs(walletOwner) == 0) return false;
            if (!kintoID.isKYC(IKintoWallet(walletOwner).owners(0))) return false;
            return true;
        }

        if (destination == address(0)) {
            // CREATE is not allowed
            return false;
        }

        return false;
    }

    /// @inheritdoc IKintoAppRegistry
    function getSystemApps() external view returns (address[] memory) {
        return systemApps;
    }

    /// @inheritdoc IKintoAppRegistry
    function getSystemContracts() external view returns (address[] memory) {
        return systemContracts;
    }

    /// @inheritdoc IKintoAppRegistry
    function getReservedContracts() external view returns (address[] memory) {
        return reservedContracts;
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
            address appContract = appContracts[i];
            if (walletFactory.walletTs(appContract) > 0) revert CannotRegisterWallet(appContract);
            if (
                childToParentContract[appContract] != address(0) && childToParentContract[appContract] != parentContract
            ) revert ChildAlreadyRegistered(appContract);
            if (appContract == parentContract) revert ChildAlreadyRegistered(appContract);
            if (isReservedContract[appContract]) revert ReservedContract(appContract);
            if (appContract.code.length == 0) revert ContractHasNoBytecode(appContract);

            childToParentContract[appContract] = parentContract;
        }

        for (uint256 i = 0; i < devEOAs.length; i++) {
            if (devEOAs[i].code.length > 0) revert DevEoaIsContract(devEOAs[i]);
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

contract KintoAppRegistryV17 is KintoAppRegistry {
    constructor(IKintoWalletFactory _walletFactory, SponsorPaymaster _paymaster)
        KintoAppRegistry(_walletFactory, _paymaster)
    {}
}
