// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import '@openzeppelin/contracts/utils/cryptography/ECDSA.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';

import '@aa/core/BaseAccount.sol';
import '@aa/samples/callback/TokenCallbackHandler.sol';

import '../interfaces/IKintoID.sol';
import '../interfaces/IKintoWallet.sol';
import '../interfaces/IKintoWalletFactory.sol';

import 'forge-std/console2.sol';

/* solhint-disable avoid-low-level-calls */
/* solhint-disable no-inline-assembly */
/* solhint-disable reason-string */

/**
  * @title KintoWallet
  * @dev Kinto Smart Contract Wallet. Supports EIP-4337.
  *     has execute, eth handling methods and has a single signer 
  *     that can send requests through the entryPoint.
  */
contract KintoWallet is Initializable, BaseAccount, TokenCallbackHandler, UUPSUpgradeable, IKintoWallet {
    using ECDSA for bytes32;

    /* ============ State Variables ============ */
    IKintoID public override immutable kintoID;
    IEntryPoint private immutable _entryPoint;

    uint8 public constant override MAX_SIGNERS = 3;
    uint8 public constant override SINGLE_SIGNER = 1;
    uint8 public constant override MINUS_ONE_SIGNER = 2;
    uint8 public constant override ALL_SIGNERS = 3;
    uint public constant override RECOVERY_TIME = 7 days;

    IKintoWalletFactory override public factory;
    uint8 public override signerPolicy = 1; // 1 = single signer, 2 = n-1 required, 3 = all required
    uint public override inRecovery; // 0 if not in recovery, timestamp when initiated otherwise

    address[] public override owners;
    address[] public override withdrawalWhitelist;

    /* ============ Events ============ */
    event KintoWalletInitialized(IEntryPoint indexed entryPoint, address indexed owner);
    event WalletPolicyChanged(uint newPolicy, uint oldPolicy);

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
    function initialize(address anOwner) external virtual initializer {
        __UUPSUpgradeable_init();
        owners.push(anOwner);
        signerPolicy = SINGLE_SIGNER;
        factory = IKintoWalletFactory(msg.sender);
        emit KintoWalletInitialized(_entryPoint, anOwner);
    }


    /* ============ Execution methods ============ */
    
    /**
     * execute a transaction (called directly from owner, or by entryPoint)
     */
    function execute(address dest, uint256 value, bytes calldata func) external override {
        _requireFromEntryPoint();
        _call(dest, value, func);
    }

    /**
     * execute a sequence of transactions
     */
    function executeBatch(address[] calldata dest, bytes[] calldata func) external override {
        _requireFromEntryPoint();
        require(dest.length == func.length, 'wrong array lengths');
        for (uint256 i = 0; i < dest.length; i++) {
            _call(dest[i], 0, func[i]);
        }
    }

    /* ============ Signer Management ============ */
    
    /**
     * @dev Change the signer policy
     * @param policy new policy
     */
    function setSignerPolicy(uint8 policy) external override onlySelf {
        require(policy > 0 && policy < 4  && policy != signerPolicy, 'invalid policy');
        require(policy == 1 || owners.length > 1, 'invalid policy');
        emit WalletPolicyChanged(policy, signerPolicy);
        signerPolicy = policy;
    }

    /**
     * @dev Changed the signers
     * @param newSigners new signers array
     */
    function resetSigners(address[] calldata newSigners) external override onlySelf {
        _resetSigners(newSigners);
    }

    /* ============ Whitelist Management ============ */

    /**
     * @dev Changed the valid withdrawal addresses
     * @param newWhitelist new signers array
     */
    function resetWithdrawalWhitelist(address[] calldata newWhitelist) external override onlySelf {
        withdrawalWhitelist = newWhitelist;
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
     * Can only be called by the factory through a privileged signer\
     * @param newSigners new signers array
     */
    function finishRecovery(address[] calldata newSigners) external override onlyFactory {
        require(block.timestamp > 0 && block.timestamp > (inRecovery + RECOVERY_TIME), 'too early');
        _resetSigners(newSigners);
        inRecovery = 0;
    }

    /**
     * @dev Cancel the recovery process
     * Can only be called by the account holder if he regains access to his wallet
     */
    function cancelRecovery() external override onlySelf {
        inRecovery = 0;
    }

    /* ============ View Functions ============ */

    // @inheritdoc BaseAccount
    function entryPoint() public view virtual override returns (IEntryPoint) {
        return _entryPoint;
    }

    function getNonce() public view virtual override(BaseAccount, IKintoWallet) returns (uint) {
        return super.getNonce();
    }

    function getOwnersCount() public view override returns (uint) {
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
        if (userOp.signature.length != 65 * owners.length) {
            return SIG_VALIDATION_FAILED;
        }
        bytes32 hash = userOpHash.toEthSignedMessageHash();
        // Single signer
        if (signerPolicy == 1 && owners.length == 1) {
            if (owners[0] != hash.recover(userOp.signature))
                return SIG_VALIDATION_FAILED;
            return 0;
        }
        uint requiredSigners = signerPolicy == 1 ? owners.length : owners.length - 1;
        bytes[] memory signatures = new bytes[](owners.length);
        // Split signature from userOp.signature
        if (owners.length == 2) {
            (signatures[0], signatures[1]) = _extractTwoSignatures(userOp.signature);
        } else {
            (signatures[0], signatures[1], signatures[2]) = _extractThreeSignatures(userOp.signature);
        }
        for (uint i = 0; i < owners.length; i++) {
            if (owners[i] == hash.recover(signatures[i])) {
                requiredSigners--;
            }
        }
        return requiredSigners;
    }

    /* ============ Private Functions ============ */

    function _resetSigners(address[] calldata newSigners) internal {
        require(newSigners.length > 0 && newSigners.length <= MAX_SIGNERS, 'invalid array');
        require(newSigners[0] != address(0) && kintoID.isKYC(newSigners[0]), 'KYC Required');
        require(newSigners.length == 1 ||
            (newSigners.length == 2 && newSigners[0] != newSigners[1]) ||
            (newSigners.length == 3 && (newSigners[0] != newSigners[1]) &&
                (newSigners[1] != newSigners[2]) && newSigners[0] != newSigners[2]),
            'duplicate owners');
        owners = newSigners;
    }

    /**
     * @dev Authorize the upgrade. Only by an owner.
     * @param newImplementation address of the new implementation
     */
    // This function is called by the proxy contract when the implementation is upgraded
    function _authorizeUpgrade(address newImplementation) internal view override {
        (newImplementation);
        _onlySelf();
    }

    function _onlySelf() internal view {
        //directly through the account itself (which gets redirected through execute())
        require(msg.sender == address(this), 'only self');
    }

    function _onlyFactory() internal view {
        //directly through the factory
        require(msg.sender == address(factory), 'only factory');
    }

    /* ============ Helpers (Move to Library) ============ */

    /**
     * @dev Executes a transaction, and send the value to the last destination
     * @param target target contract address
     * @param value eth value to send to the target
     * @param data calldata
     */
    function _call(address target, uint256 value, bytes memory data) internal {
        (bool success, bytes memory result) = target.call{value : value}(data);
        if (!success) {
            assembly {
                revert(add(result, 32), mload(result))
            }
        }
    }

    function _extractTwoSignatures(bytes memory _fullSignature)
        internal pure
        returns (bytes memory signature1, bytes memory signature2) {
        signature1 = new bytes(65);
        signature2 = new bytes(65);
        return (_extractECDASignatureFromBytes(_fullSignature, 0),
            _extractECDASignatureFromBytes(_fullSignature, 1));
    }

    function _extractThreeSignatures(bytes memory _fullSignature)
        internal pure returns (bytes memory signature1, bytes memory signature2, bytes memory signature3) {
        signature1 = new bytes(65);
        signature2 = new bytes(65);
        signature3 = new bytes(65);
        return (_extractECDASignatureFromBytes(_fullSignature, 0),
            _extractECDASignatureFromBytes(_fullSignature, 1),
            _extractECDASignatureFromBytes(_fullSignature, 2));
    }

    function _extractECDASignatureFromBytes(bytes memory _fullSignature, uint position)
        internal pure returns (bytes memory signature) {
        signature = new bytes(65);
        // Copying the first signature. Note, that we need an offset of 0x20
        // since it is where the length of the `_fullSignature` is stored
        uint firstIndex = (position * 0x40) + 0x20 + position;
        uint secondIndex = (position * 0x40) + 0x40 + position;
        uint thirdIndex = (position * 0x40) + 0x41 + position;
        assembly {
            let r := mload(add(_fullSignature, firstIndex))
            let s := mload(add(_fullSignature, secondIndex))
            let v := and(mload(add(_fullSignature, thirdIndex)), 0xff)

            mstore(add(signature, 0x20), r)
            mstore(add(signature, 0x40), s)
            mstore8(add(signature, 0x60), v)
        }
    }

}

