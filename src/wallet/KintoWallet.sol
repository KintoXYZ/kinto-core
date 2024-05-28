// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
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

import "forge-std/console2.sol";

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
    event AppKeyCreated(address indexed appKey, address indexed signer);

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
        if (dest.length != func.length || values.length != dest.length) revert LengthMismatch();
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
        if (policy == 0 || policy >= 4 || policy == signerPolicy) revert InvalidPolicy();
        if (policy != SINGLE_SIGNER && owners.length <= 1) revert InvalidPolicy();
        emit WalletPolicyChanged(policy, signerPolicy);
        signerPolicy = policy;
    }

    /**
     * @dev Change signers and policy (if new)
     * @param newSigners new signers array
     */
    function resetSigners(address[] calldata newSigners, uint8 policy) external override onlySelf {
        if (newSigners.length == 0) revert EmptySigners();
        if (newSigners[0] != owners[0]) revert InvalidSigner(); // first signer must be the same unless recovery
        _resetSigners(newSigners, policy);
    }

    /* ============ Engen Claim Simplification ============ */

    function claimEngen(uint8 firstVote, uint8 secondVote, uint8 thirdVote) external override onlySelf {
        IEngenCredits(0xD1295F0d8789c3E0931A04F91049dB33549E9C8F).mintCredits();
        EngenGovernance engenGovernance = EngenGovernance(payable(0x27926a991BB0193Bf5b679bdb6Cb3d3B6581084E));
        // Proposal Ids
        engenGovernance.castVote(
            24640268303604123367604248731438451741133735639440884241608376066048405258623, firstVote
        );
        engenGovernance.castVote(
            69259567918809410022866073051095979301361906222924053628133734242718784222981, secondVote
        );
        engenGovernance.castVote(
            26983347209218759642900171857141796671383870364224371632863277350282545068073, thirdVote
        );
        // claim commitment
        IBridgerL2(0x26181Dfc530d96523350e895180b09BAf3d816a0).claimCommitment();
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
        if (!appWhitelist[app]) revert AppNotWhitelisted();
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
        if (kintoID.isKYC(owners[0]) || !kintoID.isKYC(newSigners[0])) revert OwnerKYCMustBeBurned();
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

        // todo: remove this after engen
        // if using an app key, no calls to wallet are allowed
        if (
            (
                target == address(this)
                    && IERC20(0xD1295F0d8789c3E0931A04F91049dB33549E9C8F).balanceOf(address(this)) == 0
            ) || app == 0x3e9727470C66B1e77034590926CDe0242B5A3dCc
                || (
                    (target == 0xD1295F0d8789c3E0931A04F91049dB33549E9C8F)
                        && address(this) == 0x2e2B1c42E38f5af81771e65D87729E57ABD1337a
                )
        ) {
            return _verifySingleSignature(owners[0], hashData, userOp.signature);
        }

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
    function _verifyMultipleSignatures(bytes32 hashData, bytes memory signature) private view returns (bool) {
        // calculate required signers
        uint256 requiredSigners =
            signerPolicy == ALL_SIGNERS ? owners.length : (signerPolicy == SINGLE_SIGNER ? 1 : owners.length - 1);
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

    // @dev SINGLE_SIGNER policy expects the wallet to have only one owner though this is not enforced.
    // Any "extra" owners won't be considered when validating the signature.
    function _resetSigners(address[] calldata newSigners, uint8 _policy) internal {
        if (newSigners.length > MAX_SIGNERS) revert MaxSignersExceeded();
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

        emit SignersChanged(owners, newSigners);
        owners = newSigners;

        // change policy if needed
        if (_policy != SINGLE_SIGNER && newSigners.length == 1) revert InvalidSingleSignerPolicy();
        if (_policy != signerPolicy) {
            setSignerPolicy(_policy);
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

    function _executeInner(address dest, uint256 value, bytes calldata func) internal {
        // if target is a contract, check if it's whitelisted
        address sponsor = appRegistry.getSponsor(dest);
        if (!appWhitelist[sponsor] && dest != address(this) && sponsor != 0x3e9727470C66B1e77034590926CDe0242B5A3dCc) {
            revert AppNotWhitelisted();
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

    function isBridgeContract(address funder) private pure returns (bool) {
        return funder == 0x0f1b7bd7762662B23486320AA91F30312184f70C
            || funder == 0x361C9A99Cf874ec0B0A0A89e217Bf0264ee17a5B || funder == 0xb7DfE09Cf3950141DFb7DB8ABca90dDef8d06Ec0;
    }
}

// Upgradeable version of KintoWallet
contract KintoWalletV17 is KintoWallet {
    constructor(IEntryPoint _entryPoint, IKintoID _kintoID, IKintoAppRegistry _appRegistry)
        KintoWallet(_entryPoint, _kintoID, _appRegistry)
    {}
}
