// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@aa/core/BaseAccount.sol";
import "@aa/samples/callback/TokenCallbackHandler.sol";

import "../interfaces/IKintoID.sol";
import "../interfaces/IKintoEntryPoint.sol";
import "../interfaces/IKintoWallet.sol";
import "../interfaces/IEngenCredits.sol";
import "../interfaces/bridger/IBridgerL2.sol";
import "../governance/EngenGovernance.sol";
import "../interfaces/IKintoAppRegistry.sol";
import "../libraries/ByteSignature.sol";

/**
 * @title KintoWallet
 * @dev Kinto Smart Contract Wallet. Supports EIP-4337.
 *     has execute, eth handling methods and has a single signer
 *     that can send requests through the entryPoint.
 */
contract KintoWallet is Initializable, BaseAccount, TokenCallbackHandler, IKintoWallet {
    using ECDSA for bytes32;
    using SafeERC20 for IERC20;
    using Address for address;

    /* ============ Constants & Immutables ============ */
    IKintoID public immutable override kintoID;
    IEntryPoint private immutable _entryPoint;
    IKintoAppRegistry public immutable override appRegistry;
    IKintoWalletFactory public immutable override factory;

    uint8 public constant override MAX_SIGNERS = 4;
    uint8 public constant override SINGLE_SIGNER = 1;
    uint8 public constant override MINUS_ONE_SIGNER = 2;
    uint8 public constant override ALL_SIGNERS = 3;
    uint8 public constant override TWO_SIGNERS = 4;
    uint256 public constant override RECOVERY_TIME = 7 days;
    uint256 public constant WALLET_TARGET_LIMIT = 3; // max number of calls to wallet within a batch
    uint256 internal constant SIG_VALIDATION_SUCCESS = 0;
    address internal constant SOCKET = 0x3e9727470C66B1e77034590926CDe0242B5A3dCc;
    address internal constant ADMIN_WALLET = 0x2e2B1c42E38f5af81771e65D87729E57ABD1337a;
    address internal constant BRIDGER_MAINNET = 0x0f1b7bd7762662B23486320AA91F30312184f70C;
    address internal constant BRIDGER_ARBITRUM = 0xb7DfE09Cf3950141DFb7DB8ABca90dDef8d06Ec0;
    address internal constant BRIDGER_BASE = 0x361C9A99Cf874ec0B0A0A89e217Bf0264ee17a5B;
    address internal constant REWARDS_DISTRIBUTOR = 0xD157904639E89df05e89e0DabeEC99aE3d74F9AA;
    address internal constant KINTO_TOKEN = 0x010700808D59d2bb92257fCafACfe8e5bFF7aB87;
    address internal constant WETH = 0x0E7000967bcB5fC76A5A89082db04ed0Bf9548d8;
    address internal constant KINTO_TREASURY = 0x793500709506652Fcc61F0d2D0fDa605638D4293;

    /* ============ State Variables ============ */

    uint8 public override signerPolicy = 1; // 1 = single signer, 2 = n-1 required, 3 = all required
    uint256 public override inRecovery; // 0 if not in recovery, timestamp when initiated otherwise

    address[] public override owners;
    address public override recoverer;
    mapping(address => bool) public override funderWhitelist;
    mapping(address => address) public override appSigner;
    mapping(address => bool) public override appWhitelist;

    uint256 public override insurancePolicy = 0; // 0 = basic, 1 = premium, 2 = custom
    uint256 public override insuranceTimestamp;

    /* ============ Events ============ */

    event KintoWalletInitialized(IEntryPoint indexed entryPoint, address indexed owner);
    event WalletPolicyChanged(uint256 newPolicy, uint256 oldPolicy);
    event RecovererChanged(address indexed newRecoverer, address indexed recoverer);
    event SignersChanged(address[] newSigners, address[] oldSigners);
    event AppKeyCreated(address indexed appKey, address indexed signer);
    event InsurancePolicyChanged(uint256 indexed newPolicy, uint256 indexed oldPolicy);

    /* ============ Modifiers ============ */

    modifier onlySelf() {
        _onlySelf();
        _;
    }

    modifier onlyFactory() {
        _onlyFactory();
        _;
    }

    /* ============ Constructor & Initializers ============ */

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

    receive() external payable {}

    /**
     * @dev The _entryPoint member is immutable, to reduce gas consumption.  To upgrade EntryPoint,
     * a new implementation of SimpleAccount must be deployed with the new EntryPoint address, then upgrading
     * the implementation by calling `upgradeTo()`
     */
    function initialize(address anOwner, address _recoverer) external virtual initializer onlyFactory {
        owners.push(anOwner);
        signerPolicy = SINGLE_SIGNER;
        recoverer = _recoverer;
        emit KintoWalletInitialized(_entryPoint, anOwner);
    }

    /* ============ Execution methods ============ */

    /**
     * execute a transaction (called directly from entryPoint)
     */
    function execute(address dest, uint256 value, bytes calldata func) external override {
        _requireFromEntryPoint();
        _executeInner(dest, value, func, dest);
        // If can transact, cancel recovery
        inRecovery = 0;
    }

    /**
     * execute a sequence of transactions
     */
    function executeBatch(address[] calldata dest, uint256[] calldata values, bytes[] calldata func)
        external
        override
    {
        _requireFromEntryPoint();
        if (dest.length != func.length || values.length != dest.length) revert LengthMismatch();
        for (uint256 i = 0; i < dest.length; i++) {
            _executeInner(dest[i], values[i], func[i], dest[dest.length - 1]);
        }
        // if can transact, cancel recovery
        inRecovery = 0;
    }

    /* ============ Signer Management ============ */

    /**
     * @dev Change signer policy
     * @param newPolicy new policy
     */
    function setSignerPolicy(uint8 newPolicy) public override onlySelf {
        _checkSignerPolicy(newPolicy, owners.length);
        _setSignerPolicy(newPolicy);
    }

    /**
     * @dev Change signers and policy (if new)
     * @param newSigners new signers array
     */
    function resetSigners(address[] calldata newSigners, uint8 newPolicy) external override onlySelf {
        if (newSigners.length == 0) revert EmptySigners();
        if (newSigners[0] != owners[0]) revert InvalidSigner(); // first signer must be the same unless recovery
        _checkSignerPolicy(newPolicy, newSigners.length);

        _resetSigners(newSigners, newPolicy);
    }

    /* ============ Whitelist Management ============ */

    /**
     * @dev Changed the valid funderWhitelist addresses
     * @param newWhitelist new funders array
     * @param flags whether to allow or disallow the funder
     */
    function setFunderWhitelist(address[] calldata newWhitelist, bool[] calldata flags) external override onlySelf {
        if (newWhitelist.length != flags.length) revert LengthMismatch();
        for (uint256 i = 0; i < newWhitelist.length; i++) {
            funderWhitelist[newWhitelist[i]] = flags[i];
        }
    }

    /**
     * @dev Check if a funder is whitelisted or an owner
     * @param funder funder address
     * @return whether the funder is whitelisted
     */
    function isFunderWhitelisted(address funder) external view override returns (bool) {
        if (isBridgeContract(funder)) return true;
        for (uint256 i = 0; i < owners.length; i++) {
            if (owners[i] == funder) {
                return true;
            }
        }
        return funderWhitelist[funder];
    }

    /* ============ Token & App whitelists ============ */

    /**
     * @dev Allows the wallet to transact with specific apps
     * @param apps apps array
     * @param flags whether to allow or disallow the app
     */
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

    /* ============ App Keys ============ */

    /**
     * @dev Set the app key for a specific app
     * @param app app address
     * @param signer signer for the app
     */
    function setAppKey(address app, address signer) public override onlySelf {
        // Allow 0 in signer to allow revoking the appkey
        if (app == address(0)) revert InvalidApp();
        if (!appWhitelist[app]) revert AppNotWhitelisted(app, address(0));
        if (appSigner[app] == signer) revert InvalidSigner();
        appSigner[app] = signer;
        emit AppKeyCreated(app, signer);
    }

    /**
     * @dev Whitelist an app and set the app key
     * @param app app address
     * @param signer signer for the app
     */
    function whitelistAppAndSetKey(address app, address signer) external override onlySelf {
        appWhitelist[app] = true;
        setAppKey(app, signer);
    }

    /* ============ Recovery Process ============ */

    /**
     * @dev Start the recovery process
     * Can only be called by the factory through a privileged signer
     */
    function startRecovery() external override onlyFactory {
        inRecovery = block.timestamp;
    }

    /**
     * @dev Finish the recovery process and resets the signers
     * Can only be called by the factory through a privileged signer
     * @param newSigners new signers array
     */
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

    /**
     * @dev Change the recoverer
     * @param newRecoverer new recoverer address
     */
    function changeRecoverer(address newRecoverer) external override onlyFactory {
        if (newRecoverer == address(0) || newRecoverer == recoverer) revert InvalidRecoverer();
        emit RecovererChanged(newRecoverer, recoverer);
        recoverer = newRecoverer;
    }

    /**
     * @dev Cancel the recovery process
     * Can only be called by the account holder if he regains access to his wallet
     */
    function cancelRecovery() public override onlySelf {
        if (inRecovery > 0) {
            inRecovery = 0;
        }
    }

    /* ============ Insurance Policy ============ */

    /**
     * @dev Set the premium policy
     * @param newPolicy new policy
     * @param paymentToken token to pay for the policy
     */
    function setInsurancePolicy(uint256 newPolicy, address paymentToken) external override onlySelf {
        if (paymentToken != WETH && paymentToken != KINTO_TOKEN) revert InvalidInsurancePayment(paymentToken);
        if (newPolicy > 2 || newPolicy == insurancePolicy) revert InvalidInsurancePolicy(newPolicy);

        uint256 paymentAmount = getInsurancePrice(newPolicy, paymentToken);
        IERC20(paymentToken).safeTransfer(KINTO_TREASURY, paymentAmount);

        emit InsurancePolicyChanged(newPolicy, insurancePolicy);
        insurancePolicy = newPolicy;
        insuranceTimestamp = block.timestamp;
    }

    /**
     * @dev Get the price of the policy
     * @param newPolicy new policy
     * @param paymentToken token to pay for the policy
     */
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

    function getOwnersCount() external view override returns (uint256) {
        return owners.length;
    }

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
        address app = appRegistry.getSponsor(target);
        bytes32 hashData = userOpHash.toEthSignedMessageHash();

        // todo: remove socket once the app key flow and pimlico errors are gone
        if ((app == SOCKET || app == REWARDS_DISTRIBUTOR) && address(this) != ADMIN_WALLET) {
            if (_verifySingleSignature(owners[0], hashData, userOp.signature) == SIG_VALIDATION_SUCCESS) {
                return ((target != address(this)) && (!batch || _verifyBatch(app, userOp.callData, true)))
                    ? SIG_VALIDATION_SUCCESS
                    : SIG_VALIDATION_FAILED;
            }
            return SIG_VALIDATION_FAILED;
        }

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

    /// @dev when `executeBatch` batches user actions, we use the last action on the batch to identify who is the sponsor that will
    // be paying for all the actions within that batch. The following rules must be met:
    // - all targets must be either a sponsored contract or a child (same if using an app key)
    // - no more than WALLET_TARGET_LIMIT ops allowed. If using an app key, NO wallet calls are allowed
    function _verifyBatch(address sponsor, bytes calldata callData, bool appKey) private view returns (bool) {
        (address[] memory targets,,) = abi.decode(callData[4:], (address[], uint256[], bytes[]));
        uint256 walletCalls = 0;

        // if app key is true, ensure its rules are respected (no wallet calls are allowed and all targets are sponsored or child)
        if (appKey) {
            for (uint256 i = 0; i < targets.length; i++) {
                if (targets[i] == address(this) || !appRegistry.isSponsored(sponsor, targets[i])) {
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
                } else if (!appRegistry.isSponsored(sponsor, targets[i])) {
                    return false;
                }
            }
        }
        return true;
    }

    // @notice ensures signer has signed the hash
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

    // @notice ensures required signers have signed the hash
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
     * @dev Change signer policy
     * @param newPolicy new policy
     */
    function _setSignerPolicy(uint8 newPolicy) internal {
        if (newPolicy == 0 || newPolicy > 4 || newPolicy == signerPolicy) {
            revert InvalidPolicy(newPolicy, owners.length);
        }

        emit WalletPolicyChanged(newPolicy, signerPolicy);
        signerPolicy = newPolicy;
    }

    // @dev SINGLE_SIGNER policy expects the wallet to have only one owner though this is not enforced.
    // Any "extra" owners won't be considered when validating the signature.
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

    function _onlySelf() internal view {
        // directly through the account itself (which gets redirected through execute())
        if (msg.sender != address(this)) revert OnlySelf();
    }

    function _onlyFactory() internal view {
        //directly through the factory
        if (msg.sender != IKintoEntryPoint(address(_entryPoint)).walletFactory()) revert OnlyFactory();
    }

    function _executeInner(address dest, uint256 value, bytes calldata func, address lastAddress) internal {
        // if target is a contract, check if it's whitelisted
        address sponsor = appRegistry.getSponsor(lastAddress);
        bool validChild = dest == lastAddress || appRegistry.isSponsored(sponsor, dest);
        bool isNotAppSponsored = !appWhitelist[sponsor] || !validChild;
        bool isNotSystemApproved = dest != address(this) && sponsor != SOCKET && sponsor != REWARDS_DISTRIBUTOR;
        if (isNotAppSponsored && isNotSystemApproved) {
            revert AppNotWhitelisted(sponsor, dest);
        }

        dest.functionCallWithValue(func, value);
    }

    // extracts `target` contract and whether it is an execute or executeBatch call from the callData
    // @dev the last op on a batch MUST always be a contract whose sponsor is the one we want to
    // bear with the gas cost of all ops
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
