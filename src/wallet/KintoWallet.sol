// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Create2.sol";

import "@aa/core/BaseAccount.sol";
import "@aa/samples/callback/TokenCallbackHandler.sol";

import {Constants} from "@kinto-core/libraries/Const.sol";

import "@kinto-core/interfaces/IKintoID.sol";
import "@kinto-core/interfaces/IKintoEntryPoint.sol";
import "@kinto-core/interfaces/IKintoWallet.sol";
import "@kinto-core/interfaces/IEngenCredits.sol";
import "@kinto-core/interfaces/bridger/IBridgerL2.sol";
import "@kinto-core/governance/EngenGovernance.sol";
import "@kinto-core/interfaces/IKintoAppRegistry.sol";
import "@kinto-core/libraries/ByteSignature.sol";

import "forge-std/console2.sol";

/**
 * @title KintoWallet
 * @notice A smart contract wallet supporting EIP-4337 with advanced features including multi-signature support,
 *         recovery mechanisms, and app-specific integrations. This wallet is designed to work within the
 *         Kinto ecosystem, providing enhanced security and flexibility for users.
 * @dev Implements account abstraction (EIP-4337) and integrates with various Kinto ecosystem contracts
 *      such as KintoID for KYC, KintoAppRegistry for app management, and KintoWalletFactory for deployment.
 *      The contract includes sophisticated signature validation, execution methods, and recovery processes.
 *      It's designed to be upgradeable and interact securely with whitelisted applications and funders.
 */
contract KintoWallet is Initializable, BaseAccount, TokenCallbackHandler, IKintoWallet {
    using ECDSA for bytes32;
    using SafeERC20 for IERC20;
    using Address for address;

    /* ============ Constants & Immutables ============ */

    /// @inheritdoc IKintoWallet
    IKintoID public immutable override kintoID;

    /// @dev The EntryPoint contract
    IEntryPoint private immutable _entryPoint;

    /// @inheritdoc IKintoWallet
    IKintoAppRegistry public immutable override appRegistry;

    /// @inheritdoc IKintoWallet
    IKintoWalletFactory public immutable override factory;

    /// @inheritdoc IKintoWallet
    uint8 public constant override MAX_SIGNERS = 4;

    /// @inheritdoc IKintoWallet
    uint8 public constant override SINGLE_SIGNER = 1;

    /// @inheritdoc IKintoWallet
    uint8 public constant override MINUS_ONE_SIGNER = 2;

    /// @inheritdoc IKintoWallet
    uint8 public constant override ALL_SIGNERS = 3;

    /// @inheritdoc IKintoWallet
    uint8 public constant override TWO_SIGNERS = 4;

    /// @inheritdoc IKintoWallet
    uint256 public constant override RECOVERY_TIME = 7 days;

    /// @inheritdoc IKintoWallet
    uint256 public constant WALLET_TARGET_LIMIT = 5;

    /// @dev Constant indicating successful signature validation
    uint256 internal constant SIG_VALIDATION_SUCCESS = 0;

    /// @dev Address of the Bridger contract on Mainnet
    address internal constant BRIDGER_MAINNET = 0x0f1b7bd7762662B23486320AA91F30312184f70C;

    /// @dev Address of the Bridger contract on Arbitrum
    address internal constant BRIDGER_ARBITRUM = 0xb7DfE09Cf3950141DFb7DB8ABca90dDef8d06Ec0;

    /// @dev Address of the Bridger contract on Base
    address internal constant BRIDGER_BASE = 0x361C9A99Cf874ec0B0A0A89e217Bf0264ee17a5B;

    /// @dev Address of the Kinto Token contract
    address internal constant KINTO_TOKEN = 0x010700808D59d2bb92257fCafACfe8e5bFF7aB87;

    /// @dev Address of the WETH contract
    address internal constant WETH = 0x0E7000967bcB5fC76A5A89082db04ed0Bf9548d8;

    /// @dev Address of the Kinto Treasury
    address internal constant KINTO_TREASURY = 0x793500709506652Fcc61F0d2D0fDa605638D4293;
    uint256 public constant RECOVERY_PRICE = 5e18;

    /* ============ State Variables ============ */

    /// @inheritdoc IKintoWallet
    uint8 public override signerPolicy = 1;

    /// @inheritdoc IKintoWallet
    uint256 public override inRecovery;

    /// @inheritdoc IKintoWallet
    address[] public override owners;

    /// @inheritdoc IKintoWallet
    address public override recoverer;

    /// @inheritdoc IKintoWallet
    mapping(address => bool) public override funderWhitelist;

    /// @inheritdoc IKintoWallet
    mapping(address => address) public override appSigner;

    /// @inheritdoc IKintoWallet
    mapping(address => bool) public override appWhitelist;

    /// @inheritdoc IKintoWallet
    uint256 public override insurancePolicy = 0;

    /// @inheritdoc IKintoWallet
    uint256 public override insuranceTimestamp;

    /* ============ Events ============ */

    /// @notice Emitted when the wallet is initialized
    event KintoWalletInitialized(IEntryPoint indexed entryPoint, address indexed owner);

    /// @notice Emitted when the wallet policy is changed
    event WalletPolicyChanged(uint256 newPolicy, uint256 oldPolicy);

    /// @notice Emitted when the recoverer is changed
    event RecovererChanged(address indexed newRecoverer, address indexed recoverer);

    /// @notice Emitted when the signers are changed
    event SignersChanged(address[] newSigners, address[] oldSigners);

    /// @notice Emitted when an app key is created
    event AppKeyCreated(address indexed appKey, address indexed signer);

    /// @notice Emitted when the insurance policy is changed
    event InsurancePolicyChanged(uint256 indexed newPolicy, uint256 indexed oldPolicy);

    /* ============ Modifiers ============ */

    /// @notice Ensures the function is called by the wallet itself
    modifier onlySelf() {
        _onlySelf();
        _;
    }

    /// @notice Ensures the function is called by the factory
    modifier onlyFactory() {
        _onlyFactory();
        _;
    }

    /* ============ Constructor & Initializers ============ */

    /**
     * @notice Constructs the KintoWallet contract
     * @param __entryPoint The EntryPoint contract address
     * @param _kintoID The KintoID contract address
     * @param _kintoApp The KintoAppRegistry contract address
     * @param _factory The KintoWalletFactory contract address
     */
    constructor(
        IEntryPoint __entryPoint,
        IKintoID _kintoID,
        IKintoAppRegistry _kintoApp,
        IKintoWalletFactory _factory
    ) {
        _entryPoint = __entryPoint;
        kintoID = _kintoID;
        appRegistry = _kintoApp;
        factory = _factory;
        _disableInitializers();
    }

    /// @notice Allows the contract to receive Ether
    receive() external payable {}

    /// @inheritdoc IKintoWallet
    function initialize(address anOwner, address _recoverer) external virtual initializer onlyFactory {
        owners.push(anOwner);
        signerPolicy = SINGLE_SIGNER;
        recoverer = _recoverer;
        emit KintoWalletInitialized(_entryPoint, anOwner);
    }

    /* ============ Execution methods ============ */

    /// @inheritdoc IKintoWallet
    function execute(address dest, uint256 value, bytes calldata func) external override {
        _requireFromEntryPoint();
        _executeInner(dest, value, func, dest);
        // If can transact, cancel recovery
        inRecovery = 0;
    }

    /// @inheritdoc IKintoWallet
    function executeBatch(address[] calldata dest, uint256[] calldata values, bytes[] calldata func)
        external
        override
    {
        _requireFromEntryPoint();
        if (dest.length != func.length || values.length != dest.length) revert LengthMismatch();
        address lastDest = dest[dest.length - 1];
        for (uint256 i = 0; i < dest.length; i++) {
            _executeInner(dest[i], values[i], func[i], lastDest);
        }
        // if can transact, cancel recovery
        inRecovery = 0;
    }

    /* ============ Signer Management ============ */

    /// @inheritdoc IKintoWallet
    function setSignerPolicy(uint8 newPolicy) public override onlySelf {
        _checkSignerPolicy(newPolicy, owners.length);
        _setSignerPolicy(newPolicy);
    }

    /// @inheritdoc IKintoWallet
    function resetSigners(address[] calldata newSigners, uint8 newPolicy) external override onlySelf {
        if (newSigners.length == 0) revert EmptySigners();
        if (newSigners[0] != owners[0]) revert InvalidSigner(); // first signer must be the same unless recovery
        _checkSignerPolicy(newPolicy, newSigners.length);

        _resetSigners(newSigners, newPolicy);
    }

    /* ============ Whitelist Management ============ */

    /// @inheritdoc IKintoWallet
    function setFunderWhitelist(address[] calldata newWhitelist, bool[] calldata flags) external override onlySelf {
        if (newWhitelist.length != flags.length) revert LengthMismatch();
        for (uint256 i = 0; i < newWhitelist.length; i++) {
            funderWhitelist[newWhitelist[i]] = flags[i];
        }
    }

    /// @inheritdoc IKintoWallet
    function isFunderWhitelisted(address funder) external view override returns (bool) {
        if (isBridgeContract(funder)) return true;
        if (getAccessPoint() == funder) return true;
        for (uint256 i = 0; i < owners.length; i++) {
            if (owners[i] == funder) {
                return true;
            }
        }
        return funderWhitelist[funder];
    }

    /// @inheritdoc IKintoWallet
    function getAccessPoint() public view returns (address) {
        return Create2.computeAddress(
            bytes32(abi.encodePacked(owners[0])),
            keccak256(
                abi.encodePacked(
                    // The reason we need to import the exact bytecode is that Solidity adds metadata,
                    // including an IPFS hash, to the bytecode,
                    // which may change even if the actual bytecode remains the same.
                    Constants.safeBeaconProxyCreationCode,
                    // access beacon
                    abi.encode(
                        address(0xfe56e9D6F04D427D557dff1615398632BB7Dd3e6),
                        abi.encodeWithSignature("initialize(address)", owners[0])
                    )
                )
            ),
            // access registry
            0xA000000eaA652c7023530b603844471294B811c4
        );
    }

    /* ============ Token & App whitelists ============ */

    /// @inheritdoc IKintoWallet
    function whitelistApp(address[] calldata apps, bool[] calldata flags) external override onlySelf {
        if (apps.length != flags.length) revert LengthMismatch();
        for (uint256 i = 0; i < apps.length; i++) {
            // Revoke app key if app is removed
            if (!flags[i] && appSigner[apps[i]] != address(0)) {
                appSigner[apps[i]] = address(0);
            }
            appWhitelist[apps[i]] = flags[i];
        }
    }

    /// @inheritdoc IKintoWallet
    function isAppApproved(address app) external view override returns (bool) {
        return appWhitelist[app] || appRegistry.isSystemApp(app);
    }

    /* ============ App Keys ============ */

    /// @inheritdoc IKintoWallet
    function setAppKey(address app, address signer) public override onlySelf {
        // Allow 0 in signer to allow revoking the appkey
        if (app == address(0)) revert InvalidApp();
        if (!appWhitelist[app]) revert AppNotWhitelisted(app, address(0));
        if (appSigner[app] == signer) revert InvalidSigner();
        appSigner[app] = signer;
        emit AppKeyCreated(app, signer);
    }

    /// @inheritdoc IKintoWallet
    function whitelistAppAndSetKey(address app, address signer) external override onlySelf {
        appWhitelist[app] = true;
        setAppKey(app, signer);
    }

    /* ============ Recovery Process ============ */

    /// @inheritdoc IKintoWallet
    function startRecovery() external override onlyFactory {
        IERC20(KINTO_TOKEN).safeTransfer(KINTO_TREASURY, RECOVERY_PRICE);
        inRecovery = block.timestamp;
    }

    /// @inheritdoc IKintoWallet
    function completeRecovery(address[] calldata newSigners) external override onlyFactory {
        if (newSigners.length == 0) revert EmptySigners();
        if (inRecovery == 0) revert RecoveryNotStarted();
        if (block.timestamp <= (inRecovery + RECOVERY_TIME)) revert RecoveryTimeNotElapsed();
        if (owners[0] != newSigners[0] && (kintoID.isKYC(owners[0]) || !kintoID.isKYC(newSigners[0]))) {
            revert OwnerKYCMustBeBurned();
        }
        _resetSigners(newSigners, SINGLE_SIGNER);
        inRecovery = 0;
    }

    /// @inheritdoc IKintoWallet
    function changeRecoverer(address newRecoverer) external override onlyFactory {
        if (newRecoverer == address(0) || newRecoverer == recoverer) revert InvalidRecoverer();
        emit RecovererChanged(newRecoverer, recoverer);
        recoverer = newRecoverer;
    }

    /// @inheritdoc IKintoWallet
    function cancelRecovery() public override onlySelf {
        if (inRecovery > 0) {
            inRecovery = 0;
        }
    }

    /* ============ Insurance Policy ============ */

    /// @inheritdoc IKintoWallet
    function setInsurancePolicy(uint256 newPolicy, address paymentToken) external override onlySelf {
        if (paymentToken != WETH && paymentToken != KINTO_TOKEN) revert InvalidInsurancePayment(paymentToken);
        if (newPolicy > 2 || newPolicy == insurancePolicy) revert InvalidInsurancePolicy(newPolicy);

        uint256 paymentAmount = getInsurancePrice(newPolicy, paymentToken);
        IERC20(paymentToken).safeTransfer(KINTO_TREASURY, paymentAmount);

        emit InsurancePolicyChanged(newPolicy, insurancePolicy);
        insurancePolicy = newPolicy;
        insuranceTimestamp = block.timestamp;
    }

    /// @inheritdoc IKintoWallet
    function getInsurancePrice(uint256 newPolicy, address paymentToken) public pure override returns (uint256) {
        uint256 basicPrice = 10e18;
        if (paymentToken == WETH) {
            basicPrice = 0.03e18;
        }
        return newPolicy == 1 ? basicPrice : basicPrice * 8;
    }

    /* ============ View Functions ============ */

    // @inheritdoc BaseAccount
    function entryPoint() public view virtual override returns (IEntryPoint) {
        return _entryPoint;
    }

    function getNonce() public view virtual override(BaseAccount, IKintoWallet) returns (uint256) {
        return super.getNonce();
    }

    /// @inheritdoc IKintoWallet
    function getOwnersCount() external view override returns (uint256) {
        return owners.length;
    }

    /// @inheritdoc IKintoWallet
    function getOwners() external view override returns (address[] memory) {
        return owners;
    }

    function isBridgeContract(address funder) private pure returns (bool) {
        return funder == BRIDGER_MAINNET || funder == BRIDGER_BASE || funder == BRIDGER_ARBITRUM;
    }

    /* ============ ValidateSignature ============ */

    /// implement template method of BaseAccount
    /// @dev we don't want to do requires here as it would revert the whole transaction
    /// @dev this is very similar to SponsorPaymaster._decodeCallData, consider unifying
    function _validateSignature(UserOperation calldata userOp, bytes32 userOpHash)
        internal
        virtual
        override
        returns (uint256 validationData)
    {
        if (!kintoID.isKYC(owners[0])) return SIG_VALIDATION_FAILED; // check first owner is KYC'ed

        (address target, bool batch) = _decodeCallData(userOp.callData);
        address app = appRegistry.getApp(target);
        bytes32 hashData = userOpHash.toEthSignedMessageHash();

        // if using an app key, no calls to wallet are allowed
        // check if an app key is set
        if (appSigner[app] != address(0)) {
            if (_verifySingleSignature(appSigner[app], hashData, userOp.signature) == SIG_VALIDATION_SUCCESS) {
                return ((target != address(this)) && (!batch || _verifyBatch(app, userOp.callData, true)))
                    ? SIG_VALIDATION_SUCCESS
                    : SIG_VALIDATION_FAILED;
            }
        }

        // if app key is not set or signature is not valid, verify signer policy
        if (
            (
                signerPolicy == SINGLE_SIGNER
                    && _verifySingleSignature(owners[0], hashData, userOp.signature) == SIG_VALIDATION_SUCCESS
            ) || (signerPolicy != SINGLE_SIGNER && _verifyMultipleSignatures(hashData, userOp.signature))
        ) {
            // allow wallet calls based on batch rules
            return
                (!batch || _verifyBatch(app, userOp.callData, false)) ? SIG_VALIDATION_SUCCESS : SIG_VALIDATION_FAILED;
        }

        return SIG_VALIDATION_FAILED;
    }

    /* ============ Internal/Private Functions ============ */

    /**
     * @notice Verifies batch operations in user actions
     * @dev When `executeBatch` batches user actions, we use the last action
     *  on the batch to identify the app that will
     * be paying for all the actions within that batch. The following rules must be met:
     * - All targets must be either a sponsored contract or a child (same if using an app key)
     * - No more than WALLET_TARGET_LIMIT ops allowed. If using an app key, NO wallet calls are allowed
     * @param app The address of the sponsoring contract
     * @param callData The calldata of the batch operation
     * @param appKey Whether an app key is being used
     * @return bool Indicates whether the batch operation is valid
     */
    function _verifyBatch(address app, bytes calldata callData, bool appKey) private view returns (bool) {
        (address[] memory targets,,) = abi.decode(callData[4:], (address[], uint256[], bytes[]));
        uint256 walletCalls = 0;

        // if app key is true, ensure its rules are respected (no wallet calls are allowed and all targets are sponsored or child)
        if (appKey) {
            for (uint256 i = 0; i < targets.length; i++) {
                if (targets[i] == address(this) || !appRegistry.isSponsored(app, targets[i])) {
                    return false;
                }
            }
        } else {
            // if not set, ensure all targets are sponsored or child and that the wallet call limit is respected
            for (uint256 i = 0; i < targets.length; i++) {
                if (targets[i] == address(this)) {
                    walletCalls++;
                    if (walletCalls > WALLET_TARGET_LIMIT) {
                        return false;
                    }
                } else if (!appRegistry.isSponsored(app, targets[i])) {
                    return false;
                }
            }
        }
        return true;
    }

    /**
     * @notice Verifies a single signature against a given signer and data hash
     * @dev Uses ECDSA recovery to verify the signature
     * @param signer The address of the signer
     * @param hashData The hash of the data to be signed
     * @param signature The signature to verify
     * @return uint256 Returns SIG_VALIDATION_SUCCESS if the signature is valid, SIG_VALIDATION_FAILED otherwise
     */
    function _verifySingleSignature(address signer, bytes32 hashData, bytes memory signature)
        private
        pure
        returns (uint256)
    {
        if (signer != hashData.recover(signature)) {
            return SIG_VALIDATION_FAILED;
        }
        return _packValidationData(false, 0, 0);
    }

    /**
     * @notice Verifies multiple signatures against a given data hash
     * @dev Checks if the required number of valid signatures are present based on the current signer policy
     * @param hashData The hash of the data to be signed
     * @param signature The concatenated signatures to verify
     * @return bool Indicates whether the required number of valid signatures are present
     */
    function _verifyMultipleSignatures(bytes32 hashData, bytes memory signature) private view returns (bool) {
        // calculate required signers
        uint256 requiredSigners;
        if (signerPolicy == ALL_SIGNERS) {
            requiredSigners = owners.length;
        } else if (signerPolicy == SINGLE_SIGNER) {
            requiredSigners = 1;
        } else if (signerPolicy == TWO_SIGNERS) {
            requiredSigners = 2;
        } else if (signerPolicy == MINUS_ONE_SIGNER) {
            requiredSigners = owners.length - 1;
        }
        if (signature.length != 65 * requiredSigners) return false;

        // check if all required signers have signed
        bool[] memory hasSigned = new bool[](owners.length);
        bytes[] memory signatures = ByteSignature.extractSignatures(signature, requiredSigners);

        for (uint256 i = 0; i < signatures.length; i++) {
            address recovered = hashData.recover(signatures[i]);
            for (uint256 j = 0; j < owners.length; j++) {
                if (owners[j] == recovered && !hasSigned[j]) {
                    hasSigned[j] = true;
                    requiredSigners--;
                    break; // once the owner is found
                }
            }
        }

        // return true if all required signers have signed, otherwise return false
        return requiredSigners == 0;
    }

    /**
     * @notice Changes the signer policy for the wallet
     * @dev Updates the signerPolicy state variable and emits a WalletPolicyChanged event
     * @param newPolicy The new signer policy to set
     */
    function _setSignerPolicy(uint8 newPolicy) internal {
        if (newPolicy == 0 || newPolicy > 4 || newPolicy == signerPolicy) {
            revert InvalidPolicy(newPolicy, owners.length);
        }

        emit WalletPolicyChanged(newPolicy, signerPolicy);
        signerPolicy = newPolicy;
    }

    /**
     * @notice Resets the signers for the wallet and optionally changes the policy
     * @dev Updates the owners array and optionally calls _setSignerPolicy
     * @param newSigners The new set of signers
     * @param newPolicy The new signer policy to set
     */
    function _resetSigners(address[] calldata newSigners, uint8 newPolicy) internal {
        if (newSigners.length > MAX_SIGNERS) revert MaxSignersExceeded(newSigners.length);
        if (newSigners[0] == address(0) || !kintoID.isKYC(newSigners[0])) revert KYCRequired();

        // ensure no duplicate signers
        for (uint256 i = 0; i < newSigners.length; i++) {
            for (uint256 j = i + 1; j < newSigners.length; j++) {
                if (newSigners[i] == newSigners[j]) revert DuplicateSigner();
            }
        }

        // ensure all signers are valid
        for (uint256 i = 0; i < newSigners.length; i++) {
            if (newSigners[i] == address(0)) revert InvalidSigner();
        }

        // set new owners
        owners = newSigners;

        // change policy, if needed
        if (newPolicy != signerPolicy) {
            _setSignerPolicy(newPolicy);
        }

        emit SignersChanged(newSigners, owners);
    }

    /**
     * @notice Checks if the new signer policy is valid for the given number of signers
     * @dev Validates the policy against the number of signers to ensure it's a valid configuration
     * @param newPolicy The new signer policy to check
     * @param newSigners The number of new signers
     */
    function _checkSignerPolicy(uint8 newPolicy, uint256 newSigners) internal view {
        // reverting to SingleSigner is not allowed for security reasons
        if (newPolicy == SINGLE_SIGNER && signerPolicy != SINGLE_SIGNER) {
            revert InvalidPolicy(newPolicy, newSigners);
        }
        // MinusOneSigner and TwoSigners require at least 2 signers
        // SingleSigner and AllSigners are valid for all number of signers
        if (((newPolicy == MINUS_ONE_SIGNER || newPolicy == TWO_SIGNERS) && newSigners == 1)) {
            revert InvalidPolicy(newPolicy, newSigners);
        }
    }

    /**
     * @notice Ensures the function is called by the wallet itself
     * @dev Throws an error if the caller is not the wallet contract
     */
    function _onlySelf() internal view {
        // directly through the account itself (which gets redirected through execute())
        if (msg.sender != address(this)) revert OnlySelf();
    }

    /**
     * @notice Ensures the function is called by the factory
     * @dev Throws an error if the caller is not the wallet factory
     */
    function _onlyFactory() internal view {
        //directly through the factory
        if (msg.sender != IKintoEntryPoint(address(_entryPoint)).walletFactory()) revert OnlyFactory();
    }

    /**
     * @notice Executes a single transaction from the wallet
     * @dev Performs checks on the destination and executes the transaction
     * @param dest The destination address for the transaction
     * @param value The amount of ETH to send with the transaction
     * @param func The function data to execute
     * @param lastAddress The last address in the batch (used for identifying the sponsor)
     */
    function _executeInner(address dest, uint256 value, bytes calldata func, address lastAddress) internal {
        address app = appRegistry.getApp(lastAddress);
        // wallet is always whitelisted to call itself
        if (dest != address(this) && !appWhitelist[app] && !appRegistry.isSystemApp(app)) {
            revert AppNotWhitelisted(app, dest);
        }

        // wallet is always sponsored to call itself
        if (dest != address(this) && !appRegistry.isSponsored(app, dest)) {
            revert AppNotSponsored(app, dest);
        }

        dest.functionCallWithValue(func, value);
    }

    /**
     * @notice Decodes the calldata to extract target contract and operation type
     * @dev Extracts `target` contract and whether it is an execute or executeBatch call from the callData
     * The last op on a batch MUST always be a contract whose sponsor is the one we want to
     * bear with the gas cost of all ops
     * @param callData The calldata to decode
     * @return target The target contract address
     * @return batched Whether the call is a batch operation
     */
    function _decodeCallData(bytes calldata callData) private pure returns (address target, bool batched) {
        bytes4 selector = bytes4(callData[:4]); // extract the function selector from the callData

        if (selector == IKintoWallet.executeBatch.selector) {
            // decode executeBatch callData
            (address[] memory targets,,) = abi.decode(callData[4:], (address[], uint256[], bytes[]));
            if (targets.length == 0) return (address(0), false);

            // target is the last element of the batch
            target = targets[targets.length - 1];
            batched = true;
        } else if (selector == IKintoWallet.execute.selector) {
            (target,,) = abi.decode(callData[4:], (address, uint256, bytes)); // decode execute callData
        }
    }
}

// Upgradeable version of KintoWallet
contract KintoWalletV28 is KintoWallet {
    constructor(
        IEntryPoint _entryPoint,
        IKintoID _kintoID,
        IKintoAppRegistry _appRegistry,
        IKintoWalletFactory _factory
    ) KintoWallet(_entryPoint, _kintoID, _appRegistry, _factory) {}
}
