// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@aa/core/BaseAccount.sol";
import "@aa/samples/callback/TokenCallbackHandler.sol";

import "../interfaces/IKintoID.sol";
import "../interfaces/IKintoEntryPoint.sol";
import "../interfaces/IKintoWallet.sol";
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
    using Address for address;

    /* ============ State Variables ============ */
    IKintoID public immutable override kintoID;
    IEntryPoint private immutable _entryPoint;

    uint8 public constant override MAX_SIGNERS = 3;
    uint8 public constant override SINGLE_SIGNER = 1;
    uint8 public constant override MINUS_ONE_SIGNER = 2;
    uint8 public constant override ALL_SIGNERS = 3;
    uint256 public constant override RECOVERY_TIME = 7 days;
    uint256 public constant WALLET_TARGET_LIMIT = 3; // max number of calls to wallet within a batch
    uint256 internal constant SIG_VALIDATION_SUCCESS = 0;

    uint8 public override signerPolicy = 1; // 1 = single signer, 2 = n-1 required, 3 = all required
    uint256 public override inRecovery; // 0 if not in recovery, timestamp when initiated otherwise

    address[] public override owners;
    address public override recoverer;
    mapping(address => bool) public override funderWhitelist;
    mapping(address => address) public override appSigner;
    mapping(address => bool) public override appWhitelist;
    IKintoAppRegistry public immutable override appRegistry;

    /* ============ Events ============ */
    event KintoWalletInitialized(IEntryPoint indexed entryPoint, address indexed owner);
    event WalletPolicyChanged(uint256 newPolicy, uint256 oldPolicy);
    event RecovererChanged(address indexed newRecoverer, address indexed recoverer);
    event SignersChanged(address[] newSigners, address[] oldSigners);

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

    constructor(IEntryPoint __entryPoint, IKintoID _kintoID, IKintoAppRegistry _kintoApp) {
        _entryPoint = __entryPoint;
        kintoID = _kintoID;
        appRegistry = _kintoApp;
        _disableInitializers();
    }

    receive() external payable {}

    /**
     * @dev The _entryPoint member is immutable, to reduce gas consumption.  To upgrade EntryPoint,
     * a new implementation of SimpleAccount must be deployed with the new EntryPoint address, then upgrading
     * the implementation by calling `upgradeTo()`
     */
    function initialize(address anOwner, address _recoverer) external virtual initializer onlyFactory {
        // require(anOwner != _recoverer, 'recoverer and signer cannot be the same');
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
        _executeInner(dest, value, func);
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
        require(dest.length == func.length && values.length == dest.length, "KW-eb: wrong array length");
        for (uint256 i = 0; i < dest.length; i++) {
            _executeInner(dest[i], values[i], func[i]);
        }
        // if can transact, cancel recovery
        inRecovery = 0;
    }

    /* ============ Signer Management ============ */

    /**
     * @dev Change signer policy
     * @param policy new policy
     */
    function setSignerPolicy(uint8 policy) public override onlySelf {
        require(policy > 0 && policy < 4 && policy != signerPolicy, "KW-sp: invalid policy");
        require(policy == 1 || owners.length > 1, "invalid policy");
        emit WalletPolicyChanged(policy, signerPolicy);
        signerPolicy = policy;
    }

    /**
     * @dev Change signers and policy (if new)
     * @param newSigners new signers array
     */
    function resetSigners(address[] calldata newSigners, uint8 policy) external override onlySelf {
        require(newSigners[0] == owners[0], "KW-rs: first signer must be the same unless recovery");
        _resetSigners(newSigners, policy);
    }

    /* ============ Whitelist Management ============ */

    /**
     * @dev Changed the valid funderWhitelist addresses
     * @param newWhitelist new funders array
     * @param flags whether to allow or disallow the funder
     */
    function setFunderWhitelist(address[] calldata newWhitelist, bool[] calldata flags) external override onlySelf {
        require(newWhitelist.length == flags.length, "KW-sfw: invalid array");
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
        require(apps.length == flags.length, "KW-apw: invalid array");
        for (uint256 i = 0; i < apps.length; i++) {
            appWhitelist[apps[i]] = flags[i];
        }
    }

    /* ============ App Keys ============ */

    /**
     * @dev Set the app key for a specific app
     * @param app app address
     * @param signer signer for the app
     */
    function setAppKey(address app, address signer) external override onlySelf {
        // Allow 0 in signer to allow revoking the appkey
        require(app != address(0), "KW-apk: invalid address");
        require(appWhitelist[app], "KW-apk: contract not whitelisted"); // todo: i don't think we need to check this here
        require(appSigner[app] != signer, "KW-apk: same key");
        appSigner[app] = signer;
        // todo: emit event
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
    function completeRecovery(address[] calldata newSigners, uint8 _newPolicy) external override onlyFactory {
        require(inRecovery > 0 && block.timestamp > (inRecovery + RECOVERY_TIME), "KW-fr: too early");
        require(!kintoID.isKYC(owners[0]) && kintoID.isKYC(newSigners[0]), "KW-fr: Old KYC must have been transferred");
        _resetSigners(newSigners, _newPolicy);
        inRecovery = 0;
    }

    /**
     * @dev Change the recoverer
     * @param newRecoverer new recoverer address
     */
    function changeRecoverer(address newRecoverer) external override onlyFactory {
        require(newRecoverer != address(0) && newRecoverer != recoverer, "KW-cr: invalid address");
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

    /* ============ IAccountOverrides ============ */

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

        // check if an app key is set
        if (appSigner[app] != address(0)) {
            if (_verifySingleSignature(appSigner[app], hashData, userOp.signature) == SIG_VALIDATION_SUCCESS) {
                // if using an app key, no calls to wallet are allowed
                return (target != address(this) && (!batch || _verifyBatch(app, userOp.callData, true)))
                    ? SIG_VALIDATION_SUCCESS
                    : SIG_VALIDATION_FAILED;
            }
        }

        // if app key is not set or signature is not valid, verify signer policy
        if (
            (
                signerPolicy == SINGLE_SIGNER && owners.length == 1
                    && _verifySingleSignature(owners[0], hashData, userOp.signature) == SIG_VALIDATION_SUCCESS
            )
                || (
                    signerPolicy != SINGLE_SIGNER
                        && _verifyMultipleSignatures(hashData, userOp.signature) == SIG_VALIDATION_SUCCESS
                )
        ) {
            // allow wallet calls based on batch rules
            return
                (!batch || _verifyBatch(app, userOp.callData, false)) ? SIG_VALIDATION_SUCCESS : SIG_VALIDATION_FAILED;
        }

        return SIG_VALIDATION_FAILED;
    }

    /* ============ Internal/Private Functions ============ */

    /// @dev when `executeBatch`batches user operations, we use the last op on the batch to identify who is the sponsor that will
    // be paying for all the ops within that batch. The following rules must be met:
    // - all targets must be either a sponsored contract or a child (same if using an app key)
    // - no more than WALLET_TARGET_LIMIT ops allowed. If using an app key, NO wallet calls are allowed
    function _verifyBatch(address sponsor, bytes calldata callData, bool appKey) private view returns (bool) {
        (address[] memory targets,,) = abi.decode(callData[4:], (address[], uint256[], bytes[]));
        uint256 walletCalls = 0;

        // if app key is true, ensure its rules are respected (no wallet calls are allowed and all targets are sponsored or child)
        if (appKey) {
            for (uint256 i = 0; i < targets.length; i++) {
                if (targets[i] == address(this) || !_isSponsoredOrChild(sponsor, targets[i])) {
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
                } else if (!_isSponsoredOrChild(sponsor, targets[i])) {
                    return false;
                }
            }
        }
        return true;
    }

    function _isSponsoredOrChild(address sponsor, address target) private view returns (bool) {
        return appRegistry.isSponsored(sponsor, target) || appRegistry.childToParentContract(target) == sponsor;
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
    function _verifyMultipleSignatures(bytes32 hashData, bytes memory signature) private view returns (uint256) {
        // calculate required signers
        uint256 requiredSigners =
            signerPolicy == ALL_SIGNERS ? owners.length : (signerPolicy == SINGLE_SIGNER ? 1 : owners.length - 1);
        if (signature.length != 65 * requiredSigners) return SIG_VALIDATION_FAILED;

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

        // return success (0) if all required signers have signed, otherwise return failure (1)
        return _packValidationData(requiredSigners != 0, 0, 0);
    }

    // @dev SINGLE_SIGNER policy expects the wallet to have only one owner though this is not enforced.
    // Any "extra" owners won't be considered when validating the signature.
    function _resetSigners(address[] calldata newSigners, uint8 _policy) internal {
        require(newSigners.length > 0 && newSigners.length <= MAX_SIGNERS, "KW-rs: signers exceed max limit");
        require(newSigners[0] != address(0) && kintoID.isKYC(newSigners[0]), "KW-rs: KYC Required");

        // ensure no duplicate signers
        for (uint256 i = 0; i < newSigners.length; i++) {
            for (uint256 j = i + 1; j < newSigners.length; j++) {
                require(newSigners[i] != newSigners[j], "KW-rs: duplicate signers");
            }
        }

        // ensure all signers are valid
        for (uint256 i = 0; i < newSigners.length; i++) {
            require(newSigners[i] != address(0), "KW-rs: invalid signer address");
        }

        emit SignersChanged(owners, newSigners);
        owners = newSigners;

        // change policy if needed
        require(_policy == 1 || newSigners.length > 1, "KW-rs: invalid policy for single signer");
        if (_policy != signerPolicy) {
            setSignerPolicy(_policy);
        }
    }

    function _onlySelf() internal view {
        // directly through the account itself (which gets redirected through execute())
        require(msg.sender == address(this), "KW: only self");
    }

    function _onlyFactory() internal view {
        //directly through the factory
        require(msg.sender == IKintoEntryPoint(address(_entryPoint)).walletFactory(), "KW: only factory");
    }

    function _executeInner(address dest, uint256 value, bytes calldata func) internal {
        // if target is a contract, check if it's whitelisted
        require(appWhitelist[appRegistry.getSponsor(dest)] || dest == address(this), "KW: contract not whitelisted");

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
contract KintoWalletV5 is KintoWallet {
    constructor(IEntryPoint _entryPoint, IKintoID _kintoID, IKintoAppRegistry _appRegistry)
        KintoWallet(_entryPoint, _kintoID, _appRegistry)
    {}
}
