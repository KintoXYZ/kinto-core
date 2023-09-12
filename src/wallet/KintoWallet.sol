// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import '@openzeppelin/contracts/utils/cryptography/ECDSA.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';

import '@aa/core/BaseAccount.sol';
import '@aa/samples/callback/TokenCallbackHandler.sol';

import '../interfaces/IKintoID.sol';

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
contract KintoWallet is Initializable, BaseAccount, TokenCallbackHandler, UUPSUpgradeable {
    using ECDSA for bytes32;

    /* ============ Events ============ */
    event KintoWalletInitialized(IEntryPoint indexed entryPoint, address indexed owner);
    event WalletPolicyChanged(uint newPolicy, uint oldPolicy);

    /* ============ State Variables ============ */
    IKintoID public immutable kintoID;
    IEntryPoint private immutable _entryPoint;

    uint8 public constant MAX_SIGNERS = 3;
    uint8 public constant SINGLE_SIGNER = 1;
    uint8 public constant MINUS_ONE_SIGNER = 2;
    uint8 public constant ALL_SIGNERS = 3;

    uint8 public signerPolicy = 1; // 1 = single signer, 2 = n-1 required, 3 = all required

    address[] public owners;

    /* ============ Modifiers ============ */

    modifier onlySelf() {
        _onlySelf();
        _;
    }
    
    function _onlySelf() internal view {
        //directly from EOA owner, or through the account itself (which gets redirected through execute())
        require(msg.sender == address(this), 'only owner');
    }

    /* ============ Constructor & Initializers ============ */

    constructor(IEntryPoint __entryPoint, IKintoID _kintoID) {
        _entryPoint = __entryPoint;
        kintoID = _kintoID;
        _disableInitializers();
    }

    /**
     * @dev The _entryPoint member is immutable, to reduce gas consumption.  To upgrade EntryPoint,
     * a new implementation of SimpleAccount must be deployed with the new EntryPoint address, then upgrading
     * the implementation by calling `upgradeTo()`
     */
    function initialize(address anOwner) public virtual initializer {
        __UUPSUpgradeable_init();
        owners.push(anOwner);
        signerPolicy = SINGLE_SIGNER;
        emit KintoWalletInitialized(_entryPoint, anOwner);
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

    // solhint-disable-next-line no-empty-blocks
    receive() external payable {}
  
    /* ============ IAccountOverrides ============ */

    /// implement template method of BaseAccount
    function _validateSignature(UserOperation calldata userOp, bytes32 userOpHash) internal override virtual returns (uint256 validationData) {
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
        if (owners.length == 2) {
            (signatures[0], signatures[1]) = _extractTwoSignatures(userOp.signature);
        } else {
            (signatures[0], signatures[1], signatures[2]) = _extractThreeSignatures(userOp.signature);
        }
        // Split signature from userOp.signature
        for (uint i = 0; i < owners.length; i++) {
            if (owners[i] == hash.recover(signatures[i])) {
                requiredSigners--;
            }
        }
        return requiredSigners;
    }

    /* ============ Execution methods ============ */
    
    /**
     * execute a transaction (called directly from owner, or by entryPoint)
     */
    function execute(address dest, uint256 value, bytes calldata func) external {
        _requireFromEntryPoint();
        _call(dest, value, func);
    }

    /**
     * execute a sequence of transactions
     */
    function executeBatch(address[] calldata dest, bytes[] calldata func) external {
        _requireFromEntryPoint();
        require(dest.length == func.length, 'wrong array lengths');
        for (uint256 i = 0; i < dest.length; i++) {
            _call(dest[i], 0, func[i]);
        }
    }

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
    /* ============ Signer Management ============ */
    
    /**
     * @dev Change the signer policy
     * @param policy new policy
     */
    function setSignerPolicy(uint8 policy) public onlySelf {
        require(policy > 0 && policy < 4  && policy != signerPolicy, 'invalid policy');
        require(policy == 1 || owners.length > 1, 'invalid policy');
        emit WalletPolicyChanged(policy, signerPolicy);
        signerPolicy = policy;
    }

    /**
     * @dev Changed the signers
     * @param newSigners new signers array
     */
    function resetSigners(address[] calldata newSigners) public onlySelf {
        require(newSigners.length > 0 && newSigners.length <= MAX_SIGNERS, 'invalid array');
        require(kintoID.isKYC(newSigners[0]), 'KYC Required');
        require(newSigners.length == 1 ||
            (newSigners.length == 2 && newSigners[0] != newSigners[1]) ||
            (newSigners.length == 3 && (newSigners[0] != newSigners[1]) && (newSigners[1] != newSigners[2]) && newSigners[0] != newSigners[2]),
            'duplicate owners');
        owners = newSigners;
    }

    /* ============ View Functions ============ */

    // @inheritdoc BaseAccount
    function entryPoint() public view virtual override returns (IEntryPoint) {
        return _entryPoint;
    }

    /* ============ Helpers (Move to Library) ============ */
    function _extractTwoSignatures(bytes memory _fullSignature) internal pure returns (bytes memory signature1, bytes memory signature2) {
        signature1 = new bytes(65);
        signature2 = new bytes(65);
        return (_extractECDASignatureFromBytes(_fullSignature, 1), _extractECDASignatureFromBytes(_fullSignature, 2));
    }

    function _extractThreeSignatures(bytes memory _fullSignature) internal pure returns (bytes memory signature1, bytes memory signature2, bytes memory signature3) {
        signature1 = new bytes(65);
        signature2 = new bytes(65);
        signature3 = new bytes(65);
        return (_extractECDASignatureFromBytes(_fullSignature, 1), _extractECDASignatureFromBytes(_fullSignature, 2), _extractECDASignatureFromBytes(_fullSignature, 3));
    }

    function _extractECDASignatureFromBytes(bytes memory _fullSignature, uint position) internal pure returns (bytes memory signature) {
        signature = new bytes(65);
        // Copying the first signature. Note, that we need an offset of 0x20
        // since it is where the length of the `_fullSignature` is stored
        uint firstIndex = (position * 0x40 + 1) + 0x20;
        uint secondIndex = (position * 0x40 + 1) + 0x40;
        uint thirdIndex = (position * 0x40 + 2) + 0x40;
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

