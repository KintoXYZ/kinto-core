// Copyright 2021-2022, Offchain Labs, Inc.
// For license information, see https://github.com/nitro/blob/master/LICENSE
// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.4;

import {
    DataTooLarge,
    GasLimitTooLarge,
    InsufficientValue,
    InsufficientSubmissionCost,
    L1Forked,
    NotAllowedOrigin,
    NotCodelessOrigin,
    NotRollupOrOwner,
    RetryableData
} from "@arbitrum/nitro-contracts/src/libraries/Error.sol";
import "@arbitrum/nitro-contracts/src/bridge/IInboxBase.sol";
import "@arbitrum/nitro-contracts/src/bridge/ISequencerInbox.sol";
import "@arbitrum/nitro-contracts/src/bridge/IBridge.sol";
import "@arbitrum/nitro-contracts/src/libraries/AddressAliasHelper.sol";
import "@arbitrum/nitro-contracts/src/libraries/CallerChecker.sol";
import "@arbitrum/nitro-contracts/src/libraries/DelegateCallAware.sol";
import {
    L1MessageType_submitRetryableTx,
    L2MessageType_unsignedContractTx,
    L2MessageType_unsignedEOATx,
    L2_MSG
} from "@arbitrum/nitro-contracts/src/libraries/MessageTypes.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/StorageSlotUpgradeable.sol";

/**
 * @title Inbox for user and contract originated messages
 * @notice Messages created via this inbox are enqueued in the delayed accumulator
 * to await inclusion in the SequencerInbox
 */
abstract contract AbsInbox is DelegateCallAware, PausableUpgradeable, IInboxBase {
    /// @dev Storage slot with the admin of the contract.
    /// This is the keccak-256 hash of "eip1967.proxy.admin" subtracted by 1.
    bytes32 internal constant _ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    /// @inheritdoc IInboxBase
    IBridge public bridge;
    /// @inheritdoc IInboxBase
    ISequencerInbox public sequencerInbox;

    /// ------------------------------------ allow list start ------------------------------------ ///

    /// @inheritdoc IInboxBase
    bool public allowListEnabled;

    /// @inheritdoc IInboxBase
    mapping(address => bool) public isAllowed;

    /// @dev mapping to whitelist contracts that do not need dusting check
    mapping(address => bool) private l2AllowList;

    event AllowListAddressSet(address indexed user, bool val);
    event AllowListEnabledUpdated(bool isEnabled);
    event L2AllowListAddressSet(address indexed user, bool val);
    event L2AllowListInitialized();

    error RefundAddressNotAllowed(address to, address excessFeeRefundAddress, address callValueRefundAddress);

    /// @notice add or remove users from l2AllowList
    function setL2AllowList(address[] memory addresses, bool[] memory values) external onlyRollupOrOwner {
        require(addresses.length == values.length, "INVALID_INPUT");

        for (uint256 i = 0; i < addresses.length; i++) {
            l2AllowList[addresses[i]] = values[i];
            emit L2AllowListAddressSet(addresses[i], values[i]);
        }
    }

    /// @inheritdoc IInboxBase
    function setAllowList(address[] memory user, bool[] memory val) external onlyRollupOrOwner {
        require(user.length == val.length, "INVALID_INPUT");

        for (uint256 i = 0; i < user.length; i++) {
            isAllowed[user[i]] = val[i];
            emit AllowListAddressSet(user[i], val[i]);
        }
    }

    /// @inheritdoc IInboxBase
    function setAllowListEnabled(bool _allowListEnabled) external onlyRollupOrOwner {
        require(_allowListEnabled != allowListEnabled, "ALREADY_SET");
        allowListEnabled = _allowListEnabled;
        emit AllowListEnabledUpdated(_allowListEnabled);
    }

    /// @dev this modifier checks the tx.origin instead of msg.sender for convenience (ie it allows
    /// allowed users to interact with the token bridge without needing the token bridge to be allowList aware).
    /// this modifier is not intended to use to be used for security (since this opens the allowList to
    /// a smart contract phishing risk).
    modifier onlyAllowed() {
        // solhint-disable-next-line avoid-tx-origin
        if (allowListEnabled && !isAllowed[tx.origin]) revert NotAllowedOrigin(tx.origin);
        _;
    }

    /// @dev this modifier ensures that both `excessFeeRefundAddress` and `callValueRefundAddress` match the msg.sender
    /// unless the `to` address is whitelisted.
    /// This check prevents users from dusting others on the L2.
    modifier whenRefundAddressAllowed(address to, address excessFeeRefundAddress, address callValueRefundAddress) {
        if (!l2AllowList[to] && (excessFeeRefundAddress != msg.sender || callValueRefundAddress != msg.sender)) {
            revert RefundAddressNotAllowed(to, excessFeeRefundAddress, callValueRefundAddress);
        }
        _;
    }

    /// ------------------------------------ allow list end ------------------------------------ ///

    modifier onlyRollupOrOwner() {
        IOwnable rollup = bridge.rollup();
        if (msg.sender != address(rollup)) {
            address rollupOwner = rollup.owner();
            if (msg.sender != rollupOwner) {
                revert NotRollupOrOwner(msg.sender, address(rollup), rollupOwner);
            }
        }
        _;
    }

    // On L1 this should be set to 117964: 90% of Geth's 128KB tx size limit, leaving ~13KB for proving
    uint256 public immutable maxDataSize;
    uint256 internal immutable deployTimeChainId = block.chainid;

    constructor(uint256 _maxDataSize) {
        maxDataSize = _maxDataSize;
    }

    function _chainIdChanged() internal view returns (bool) {
        return deployTimeChainId != block.chainid;
    }

    /// @inheritdoc IInboxBase
    function pause() external onlyRollupOrOwner {
        _pause();
    }

    /// @inheritdoc IInboxBase
    function unpause() external onlyRollupOrOwner {
        _unpause();
    }

    /* solhint-disable func-name-mixedcase */
    function __AbsInbox_init(IBridge _bridge, ISequencerInbox _sequencerInbox) internal onlyInitializing {
        bridge = _bridge;
        sequencerInbox = _sequencerInbox;
        allowListEnabled = false;
        __Pausable_init();
    }

    /// @inheritdoc IInboxBase
    function sendL2MessageFromOrigin(bytes calldata messageData) external whenNotPaused onlyAllowed returns (uint256) {
        if (_chainIdChanged()) revert L1Forked();
        if (!CallerChecker.isCallerCodelessOrigin()) revert NotCodelessOrigin();
        if (messageData.length > maxDataSize) revert DataTooLarge(messageData.length, maxDataSize);
        uint256 msgNum = _deliverToBridge(L2_MSG, msg.sender, keccak256(messageData), 0);
        emit InboxMessageDeliveredFromOrigin(msgNum);
        return msgNum;
    }

    /// @inheritdoc IInboxBase
    function sendL2Message(bytes calldata messageData) external whenNotPaused onlyAllowed returns (uint256) {
        if (_chainIdChanged()) revert L1Forked();
        return _deliverMessage(L2_MSG, msg.sender, messageData, 0);
    }

    /// @inheritdoc IInboxBase
    function sendUnsignedTransaction(
        uint256 gasLimit,
        uint256 maxFeePerGas,
        uint256 nonce,
        address to,
        uint256 value,
        bytes calldata data
    ) external whenNotPaused onlyAllowed returns (uint256) {
        // arbos will discard unsigned tx with gas limit too large
        if (gasLimit > type(uint64).max) {
            revert GasLimitTooLarge();
        }
        return _deliverMessage(
            L2_MSG,
            msg.sender,
            abi.encodePacked(
                L2MessageType_unsignedEOATx, gasLimit, maxFeePerGas, nonce, uint256(uint160(to)), value, data
            ),
            0
        );
    }

    /// @inheritdoc IInboxBase
    function sendContractTransaction(
        uint256 gasLimit,
        uint256 maxFeePerGas,
        address to,
        uint256 value,
        bytes calldata data
    ) external whenNotPaused onlyAllowed returns (uint256) {
        // arbos will discard unsigned tx with gas limit too large
        if (gasLimit > type(uint64).max) {
            revert GasLimitTooLarge();
        }
        return _deliverMessage(
            L2_MSG,
            msg.sender,
            abi.encodePacked(
                L2MessageType_unsignedContractTx, gasLimit, maxFeePerGas, uint256(uint160(to)), value, data
            ),
            0
        );
    }

    /// @inheritdoc IInboxBase
    function getProxyAdmin() external view returns (address) {
        return StorageSlotUpgradeable.getAddressSlot(_ADMIN_SLOT).value;
    }

    function _createRetryableTicket(
        address to,
        uint256 l2CallValue,
        uint256 maxSubmissionCost,
        address excessFeeRefundAddress,
        address callValueRefundAddress,
        uint256 gasLimit,
        uint256 maxFeePerGas,
        uint256 amount,
        bytes calldata data
    ) internal returns (uint256) {
        // Ensure the user's deposit alone will make submission succeed.
        // In case of native token having non-18 decimals: 'amount' is denominated in native token's decimals. All other
        // value params - l2CallValue, maxSubmissionCost and maxFeePerGas are denominated in child chain's native 18 decimals.
        uint256 amountToBeMintedOnL2 = _fromNativeTo18Decimals(amount);
        if (amountToBeMintedOnL2 < (maxSubmissionCost + l2CallValue + gasLimit * maxFeePerGas)) {
            revert InsufficientValue(maxSubmissionCost + l2CallValue + gasLimit * maxFeePerGas, amountToBeMintedOnL2);
        }

        // if a refund address is a contract, we apply the alias to it
        // so that it can access its funds on the L2
        // since the beneficiary and other refund addresses don't get rewritten by arb-os
        if (AddressUpgradeable.isContract(excessFeeRefundAddress)) {
            excessFeeRefundAddress = AddressAliasHelper.applyL1ToL2Alias(excessFeeRefundAddress);
        }
        if (AddressUpgradeable.isContract(callValueRefundAddress)) {
            // this is the beneficiary. be careful since this is the address that can cancel the retryable in the L2
            callValueRefundAddress = AddressAliasHelper.applyL1ToL2Alias(callValueRefundAddress);
        }

        // gas limit is validated to be within uint64 in unsafeCreateRetryableTicket
        return _unsafeCreateRetryableTicket(
            to,
            l2CallValue,
            maxSubmissionCost,
            excessFeeRefundAddress,
            callValueRefundAddress,
            gasLimit,
            maxFeePerGas,
            amount,
            data
        );
    }

    function _unsafeCreateRetryableTicket(
        address to,
        uint256 l2CallValue,
        uint256 maxSubmissionCost,
        address excessFeeRefundAddress,
        address callValueRefundAddress,
        uint256 gasLimit,
        uint256 maxFeePerGas,
        uint256 amount,
        bytes calldata data
    ) internal returns (uint256) {
        // gas price and limit of 1 should never be a valid input, so instead they are used as
        // magic values to trigger a revert in eth calls that surface data without requiring a tx trace
        if (gasLimit == 1 || maxFeePerGas == 1) {
            revert RetryableData(
                msg.sender,
                to,
                l2CallValue,
                amount,
                maxSubmissionCost,
                excessFeeRefundAddress,
                callValueRefundAddress,
                gasLimit,
                maxFeePerGas,
                data
            );
        }

        // arbos will discard retryable with gas limit too large
        if (gasLimit > type(uint64).max) {
            revert GasLimitTooLarge();
        }

        uint256 submissionFee = calculateRetryableSubmissionFee(data.length, block.basefee);
        if (maxSubmissionCost < submissionFee) {
            revert InsufficientSubmissionCost(submissionFee, maxSubmissionCost);
        }

        return _deliverMessage(
            L1MessageType_submitRetryableTx,
            msg.sender,
            abi.encodePacked(
                uint256(uint160(to)),
                l2CallValue,
                _fromNativeTo18Decimals(amount),
                maxSubmissionCost,
                uint256(uint160(excessFeeRefundAddress)),
                uint256(uint160(callValueRefundAddress)),
                gasLimit,
                maxFeePerGas,
                data.length,
                data
            ),
            amount
        );
    }

    function _deliverMessage(uint8 _kind, address _sender, bytes memory _messageData, uint256 amount)
        internal
        returns (uint256)
    {
        if (_messageData.length > maxDataSize) {
            revert DataTooLarge(_messageData.length, maxDataSize);
        }
        uint256 msgNum = _deliverToBridge(_kind, _sender, keccak256(_messageData), amount);
        emit InboxMessageDelivered(msgNum, _messageData);
        return msgNum;
    }

    function _deliverToBridge(uint8 kind, address sender, bytes32 messageDataHash, uint256 amount)
        internal
        virtual
        returns (uint256);

    function calculateRetryableSubmissionFee(uint256 dataLength, uint256 baseFee)
        public
        view
        virtual
        returns (uint256);

    /// @notice get amount of ETH/token to mint on child chain based on provided value.
    ///         In case of ETH-based rollup this amount will always equal the provided
    ///         value. In case of ERC20-based rollup where native token has number of
    ///         decimals different thatn 18, amount will be re-adjusted to reflect 18
    ///         decimals used for native currency on child chain.
    /// @dev    provided value has to be less than 'type(uint256).max/10**(18-decimalsIn)'
    ///         or otherwise it will overflow.
    function _fromNativeTo18Decimals(uint256 value) internal view virtual returns (uint256);

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[47] private __gap;
}
