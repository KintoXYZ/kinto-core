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

    /* ============ State Variables ============ */
    IKintoID public immutable kintoID;
    IEntryPoint private immutable _entryPoint;

    uint8 public signerPolicy = 1; // 1 = single signer, 2 = n-1 required

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
        signerPolicy = 1;
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

    /// @inheritdoc BaseAccount
    function entryPoint() public view virtual override returns (IEntryPoint) {
        return _entryPoint;
    }

    // solhint-disable-next-line no-empty-blocks
    receive() external payable {}
  
    /* ============ IAccountOverrides ============ */

    /// implement template method of BaseAccount
    function _validateSignature(UserOperation calldata userOp, bytes32 userOpHash) internal override virtual returns (uint256 validationData) {
        // Check first owner of this account is still KYC'ed
        require(kintoID.isKYC(owners[0]), 'KYC Required');
        bytes32 hash = userOpHash.toEthSignedMessageHash();
        // Single signer
        if (signerPolicy == 1 && owners.length == 1) {
            if (owners[0] != hash.recover(userOp.signature))
                return SIG_VALIDATION_FAILED;
            return 0;
        }
        uint requiredSigners = signerPolicy == 1 ? owners.length : owners.length - 1;
        // Split signature from userOp.signature
        for (uint i = 0; i < owners.length; i++) {
            if (owners[i] == hash.recover(userOp.signature)) {
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

    function _call(address target, uint256 value, bytes memory data) internal {
        (bool success, bytes memory result) = target.call{value : value}(data);
        if (!success) {
            assembly {
                revert(add(result, 32), mload(result))
            }
        }
    }
    /* ============ Signer Management ============ */

    // TODO
    // add signer
    // remove signer
    // change policy

    /* ============ Deposit and withdraw into entry point ============ */

    /**
     * Get current account deposit in the entryPoint
     */
    function getDeposit() public view returns (uint256) {
        return entryPoint().balanceOf(address(this));
    }

    /**
     * Deposit more funds for this account in the entryPoint
     */
    function addDeposit() public payable onlySelf {
        entryPoint().depositTo{value : msg.value}(address(this));
    }

    /**
     * Withdraw value from the account's deposit
     * @param withdrawAddress target to send to
     * @param amount to withdraw
     */
    function withdrawDepositTo(address payable withdrawAddress, uint256 amount) public onlySelf {
        entryPoint().withdrawTo(withdrawAddress, amount);
    }

}

