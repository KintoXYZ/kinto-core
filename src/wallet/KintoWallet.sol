// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import '@openzeppelin/contracts/utils/Address.sol';
import '@openzeppelin/contracts/utils/cryptography/ECDSA.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts/interfaces/IERC20.sol';

import '@aa/core/BaseAccount.sol';
import '@aa/samples/callback/TokenCallbackHandler.sol';


import '../interfaces/IKintoID.sol';
import '../interfaces/IKintoEntryPoint.sol';
import '../libraries/ByteSignature.sol';
import '../interfaces/IKintoWallet.sol';
import '../interfaces/IKintoWalletFactory.sol';

// import 'forge-std/console2.sol';

/* solhint-disable avoid-low-level-calls */
/* solhint-disable no-inline-assembly */
/* solhint-disable reason-string */

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
    IKintoID public override immutable kintoID;
    IEntryPoint private immutable _entryPoint;

    uint8 public constant override MAX_SIGNERS = 3;
    uint8 public constant override SINGLE_SIGNER = 1;
    uint8 public constant override MINUS_ONE_SIGNER = 2;
    uint8 public constant override ALL_SIGNERS = 3;
    uint public constant override RECOVERY_TIME = 7 days;

    uint8 public override signerPolicy = 1; // 1 = single signer, 2 = n-1 required, 3 = all required
    uint public override inRecovery; // 0 if not in recovery, timestamp when initiated otherwise

    address[] public override owners;
    address public override recoverer;
    mapping(address => bool) public override funderWhitelist;
    mapping(address => mapping (address => uint256)) private tokenApprovals;
    mapping(address => address) public override appSigner;
    mapping(address => bool) public override appWhitelist;

    /* ============ Events ============ */
    event KintoWalletInitialized(IEntryPoint indexed entryPoint, address indexed owner);
    event WalletPolicyChanged(uint newPolicy, uint oldPolicy);
    event RecovererChanged(address indexed newRecoverer, address indexed recoverer);

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

    constructor(IEntryPoint __entryPoint, IKintoID _kintoID) {
        _entryPoint = __entryPoint;
        kintoID = _kintoID;
        _disableInitializers();
    }

    // solhint-disable-next-line no-empty-blocks
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
        _execute(dest, value, func);
        // If can transact, cancel recovery
        cancelRecovery();
    }

    /**
     * execute a sequence of transactions
     */
    function executeBatch(address[] calldata dest, uint256[] calldata values, bytes[] calldata func) external override {
        _requireFromEntryPoint();
        require(dest.length == func.length && values.length == dest.length, 'wrong array lengths');
        for (uint256 i = 0; i < dest.length; i++) {
            _execute(dest[i], values[i], func[i]);
        }
        // If can transact, cancel recovery
        cancelRecovery();
    }

    /* ============ Signer Management ============ */
    
    /**
     * @dev Change the signer policy
     * @param policy new policy
     */
    function setSignerPolicy(uint8 policy) public override onlySelf {
        require(policy > 0 && policy < 4  && policy != signerPolicy, 'invalid policy');
        require(policy == 1 || owners.length > 1, 'invalid policy');
        emit WalletPolicyChanged(policy, signerPolicy);
        signerPolicy = policy;
    }

    /**
     * @dev Changed the signers
     * @param newSigners new signers array
     */
    function resetSigners(address[] calldata newSigners, uint8 policy) external override onlySelf {
        require(newSigners[0] == owners[0], 'first signer must be the same unless done through recovery');
        _resetSigners(newSigners, policy);
    }


    /* ============ Whitelist Management ============ */

    /**
     * @dev Changed the valid funderWhitelist addresses
     * @param newWhitelist new funders array
     * @param flags whether to allow or disallow the funder
     */
    function setFunderWhitelist(address[] calldata newWhitelist, bool[] calldata flags) external override onlySelf {
        require(newWhitelist.length == flags.length, 'invalid array');
        for (uint i = 0; i < newWhitelist.length; i++) {
            funderWhitelist[newWhitelist[i]] = flags[i];
        }
    }

    /**
     * @dev Check if a funder is whitelisted or an owner
     * @param funder funder address
     * @return whether the funder is whitelisted
     */
    function isFunderWhitelisted(address funder) external view override returns (bool) {
        for (uint i = 0; i < owners.length; i++) {
            if (owners[i] == funder) {
                return true;
            }
        }
        return funderWhitelist[funder];
    }

    /* ============ Token Approvals ============ */

    /**
     * @dev Approve tokens to a specific app
     * @param app app address
     * @param tokens tokens array
     * @param amount amount array
     */
    function approveTokens(
        address app,
        address[] calldata tokens,
        uint256[] calldata amount)
        external override onlySelf 
    {
        require(tokens.length == amount.length, 'invalid array');
        for (uint i = 0; i < tokens.length; i++) {
            if (tokenApprovals[app][tokens[i]] > 0) {
                IERC20(tokens[i]).approve(app, 0);
            }
            tokenApprovals[app][tokens[i]] = amount[i];
            IERC20(tokens[i]).approve(app, amount[i]);
        }
    }

    /**
     * @dev Revoke token approvals given to a specific app
     * @param app app address
     * @param tokens tokens array
     */
    function revokeTokens(
        address app,
        address[] calldata tokens)
        external override onlySelf
    {
        for (uint i = 0; i < tokens.length; i++) {
            tokenApprovals[app][tokens[i]] = 0;
            IERC20(tokens[i]).approve(app, 0);
        }
    }

    /* ============ App Keys ============ */

    /**
     * @dev Set the app key for a specific app
     * @param app app address
     * @param signer signer for the app
     */
    function setAppKey(address app, address signer) external override onlySelf {
        require(app != address(0) && signer != address(0), 'invalid address');
        require(appSigner[app] != signer, 'same key');
        appSigner[app] = signer;
    }

    /**
     * @dev Allos the wallet to transact with a specific app
     * @param apps apps array
     * @param flags whether to allow or disallow the app
     */
    function setAppWhitelist(address[] calldata apps, bool[] calldata flags) external override onlySelf {
        require(apps.length == flags.length, 'invalid array');
        for (uint i = 0; i < apps.length; i++) {
            appWhitelist[apps[i]] = flags[i];
        }
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
    function finishRecovery(address[] calldata newSigners) external override onlyFactory {
        require(inRecovery > 0 && block.timestamp > (inRecovery + RECOVERY_TIME), 'too early');
        require(!kintoID.isKYC(owners[0]), 'Old KYC must be burned');
        _resetSigners(newSigners, SINGLE_SIGNER);
        inRecovery = 0;
    }

    /**
     * @dev Change the recoverer
     * @param newRecoverer new recoverer address
     */
    function changeRecoverer(address newRecoverer) external override onlyFactory() {
        require(newRecoverer != address(0) && newRecoverer != recoverer, 'invalid address');
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

    function getNonce() public view virtual override(BaseAccount, IKintoWallet) returns (uint) {
        return super.getNonce();
    }

    function getOwnersCount() external view override returns (uint) {
        return owners.length;
    }

    /* ============ IAccountOverrides ============ */

    /// implement template method of BaseAccount
    function _validateSignature(UserOperation calldata userOp, bytes32 userOpHash)
        internal override virtual returns (uint256 validationData) {
        // We don't want to do requires here as it would revert the whole transaction
        // Check first owner of this account is still KYC'ed
        if (!kintoID.isKYC(owners[0])) {
            return SIG_VALIDATION_FAILED;
        }
        // If there is only one signature and there is an app Key, check it
        address app = _getLastTargetContract(userOp.callData);
        if (userOp.signature.length == 65 && appSigner[app] != address(0)) {
            if (appSigner[app] == userOpHash.recover(userOp.signature)) {
                return _packValidationData(false, 0, 0);
            }
        }
        if (userOp.signature.length != 65 * owners.length) {
            return SIG_VALIDATION_FAILED;
        }
        bytes32 hash = userOpHash.toEthSignedMessageHash();
        // Single signer
        if (signerPolicy == 1 && owners.length == 1) {
            if (owners[0] != hash.recover(userOp.signature))
                return SIG_VALIDATION_FAILED;
            return _packValidationData(false, 0, 0);
        }
        uint requiredSigners = signerPolicy == 3 ? owners.length : (signerPolicy == 1 ? 1 : owners.length - 1);
        bytes[] memory signatures = new bytes[](owners.length);
        // Split signature from userOp.signature
        if (owners.length == 2) {
            (signatures[0], signatures[1]) = ByteSignature.extractTwoSignatures(userOp.signature);
        } else {
            (signatures[0], signatures[1], signatures[2]) = ByteSignature.extractThreeSignatures(userOp.signature);
        }
        for (uint i = 0; i < owners.length; i++) {
            if (owners[i] == hash.recover(signatures[i])) {
                requiredSigners--;
                if (requiredSigners == 0) {
                    break;
                }
            }
        }
        return _packValidationData(requiredSigners != 0, 0, 0);
    }

    /* ============ Private Functions ============ */

    function _resetSigners(address[] calldata newSigners, uint8 _policy) internal {
        require(newSigners.length > 0 && newSigners.length <= MAX_SIGNERS, 'invalid array');
        require(newSigners[0] != address(0) && kintoID.isKYC(newSigners[0]), 'KYC Required');
        require(newSigners.length == 1 ||
            (newSigners.length == 2 && newSigners[0] != newSigners[1]) ||
            (newSigners.length == 3 && (newSigners[0] != newSigners[1]) &&
                (newSigners[1] != newSigners[2]) && newSigners[0] != newSigners[2]),
            'duplicate owners');
        owners = newSigners;
        // Change policy if needed
        if (_policy != signerPolicy) {
            setSignerPolicy(_policy);
        }
    }

    function _preventDirectApproval(bytes calldata _bytes) pure internal {
        // Prevent direct deployment of KintoWallet contracts
        bytes4 approvalBytes = bytes4(keccak256(bytes("approve(address,uint256)")));
        require(
            bytes4(keccak256(_bytes[:4])) != approvalBytes,
            'Direct ERC20 approval not allowed'
        );
    }

    function _checkAppWhitelist(address app) internal view {
        require(appWhitelist[app], 'app not whitelisted');
    }

    function _onlySelf() internal view {
        //directly through the account itself (which gets redirected through execute())
        require(msg.sender == address(this), 'only self');
    }

    function _onlyFactory() internal view {
        //directly through the factory
        require(msg.sender == IKintoEntryPoint(address(_entryPoint)).walletFactory(), 'only factory');
    }

    function _execute(address dest, uint256 value, bytes calldata func) internal {
        _requireFromEntryPoint();
        _checkAppWhitelist(dest);
        // Prevents direct approval
        _preventDirectApproval(func);
        dest.functionCallWithValue(func, value);
        // If can transact, cancel recovery
        cancelRecovery();
    }

    // Function to extract the first target contract
    function _getLastTargetContract(bytes calldata callData) private pure returns (address lastTargetContract) {
        // Extract the function selector from the callData
        bytes4 selector = bytes4(callData[:4]);

        // Compare the selector with the known function selectors
        if (selector == IKintoWallet.executeBatch.selector) {
            // Decode callData for executeBatch
            (address[] memory targetContracts,,) = abi.decode(callData[4:], (address[], uint256[], bytes[]));
            lastTargetContract = targetContracts[targetContracts.length - 1];
        } else if (selector == IKintoWallet.execute.selector) {
            // Decode callData for execute
            (address targetContract,,) = abi.decode(callData[4:], (address, uint256, bytes));
            lastTargetContract = targetContract;
        } else {
            // Handle unknown function or error
            revert('SP: Unknown function selector');
        }
    }
}

