// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin-5.0.1/contracts/utils/Address.sol";
import "@openzeppelin-5.0.1/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin-5.0.1/contracts/utils/cryptography/MessageHashUtils.sol";
import "@openzeppelin-5.0.1/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin-5.0.1/contracts/interfaces/IERC20.sol";

import {BaseAccount} from "@aa-v7/core/BaseAccount.sol";
import {UserOperationLib} from "@aa-v7/core/UserOperationLib.sol";
import {SIG_VALIDATION_FAILED, SIG_VALIDATION_SUCCESS} from "@aa-v7/core/Helpers.sol";
import {PackedUserOperation} from "@aa-v7/interfaces/PackedUserOperation.sol";
import {IEntryPoint} from "@aa-v7/interfaces/IEntryPoint.sol";
import {TokenCallbackHandler} from "@aa-v7/samples/callback/TokenCallbackHandler.sol";

import {IAccessPoint} from "@kinto-core/interfaces/IAccessPoint.sol";
import {IAccessRegistry} from "@kinto-core/interfaces/IAccessRegistry.sol";

/**
 * @title AccessPoint
 */
contract AccessPoint is IAccessPoint, Initializable, BaseAccount, TokenCallbackHandler {
    using UserOperationLib for PackedUserOperation;
    using MessageHashUtils for bytes32;

    /* ============ State Variables ============ */

    address public owner;

    IAccessRegistry public immutable override registry;
    IEntryPoint private immutable _entryPoint;

    /* ============ Modifiers ============ */

    modifier onlyFromEntryPointOrOwner() {
        _onlyFromEntryPointOrOwner();
        _;
    }

    // Require the function call went through EntryPoint or owner
    function _onlyFromEntryPointOrOwner() internal view {
        // Check that the caller is either the owner or an envoy with permission.
        if (!(msg.sender == address(entryPoint()) || msg.sender == owner)) {
            revert ExecutionUnauthorized(owner, msg.sender);
        }
    }

    /* ============ Constructor & Initializers ============ */

    /// @notice Creates the proxy by fetching the constructor params from the registry, optionally delegate calling
    /// to a target contract if one is provided.
    /// @dev The rationale of this approach is to have the proxy's CREATE2 address not depend on any constructor params.
    constructor(IEntryPoint entryPoint_, IAccessRegistry registry_) {
        registry = registry_;
        _entryPoint = entryPoint_;

        _disableInitializers();
    }

    /**
     * @dev The _entryPoint member is immutable, to reduce gas consumption.  To upgrade EntryPoint,
     * a new implementation of AccessPoint must be deployed with the new EntryPoint address.
     */
    function initialize(address owner_) external virtual initializer {
        owner = owner_;
    }

    /* ============ View Functions ============ */

    function getNonce() public view virtual override(BaseAccount, IAccessPoint) returns (uint256) {
        return super.getNonce();
    }

    /// @inheritdoc BaseAccount
    function entryPoint() public view virtual override returns (IEntryPoint) {
        return _entryPoint;
    }

    /* ============ State Change ============ */

    /* ============ Fallback Functions ============ */

    fallback(bytes calldata data) external payable returns (bytes memory) {
        revert FallbackIsNotAllowed(data);
    }

    /// @dev Called when `msg.value` is not zero and the call data is empty.
    receive() external payable {}

    /* ============ External Functions ============ */

    function execute(address target, bytes calldata data)
        external
        payable
        override
        onlyFromEntryPointOrOwner
        returns (bytes memory response)
    {
        // Delegate call to the target contract, and handle the response.
        response = _execute(target, data);
    }

    function executeBatch(address[] calldata target, bytes[] calldata data)
        external
        payable
        override
        onlyFromEntryPointOrOwner
        returns (bytes[] memory responses)
    {
        if (target.length != data.length) revert ExecuteInvalidInput();
        responses = new bytes[](target.length);
        for (uint256 index = 0; index < target.length; index++) {
            // Delegate call to the target contract, and store the response.
            responses[index] = _execute(target[index], data[index]);
        }
    }

    /* ============ Internal Functions ============ */

    /// @notice Executes a DELEGATECALL to the provided target with the provided data.
    /// @dev Shared logic between the constructor and the `execute` function.
    function _execute(address target, bytes memory data) internal returns (bytes memory response) {
        if (!registry.isWorkflowAllowed(target)) {
            revert WorkflowUnauthorized(target);
        }
        // Check that the target is a contract.
        if (target.code.length == 0) {
            revert TargetNotContract(target);
        }

        // Delegate call to the target contract.
        bool success;
        // slither-disable-start controlled-delegatecall
        // slither-disable-start delegatecall-loop
        (success, response) = target.delegatecall(data);
        // slither-disable-end controlled-delegatecall
        // slither-disable-end delegatecall-loop

        // Log the execution.
        emit Execute(target, data, response);

        // Check if the call was successful or not.
        if (!success) {
            // If there is return data, the delegate call reverted with a reason or a custom error, which we bubble up.
            if (response.length > 0) {
                assembly {
                    // The length of the data is at `response`, while the actual data is at `response + 32`.
                    let returndata_size := mload(response)
                    revert(add(response, 32), returndata_size)
                }
            } else {
                revert ExecutionReverted();
            }
        }
    }

    /// @notice Valides that owner signed the user operation
    function _validateSignature(PackedUserOperation calldata userOp, bytes32 userOpHash)
        internal
        virtual
        override
        returns (uint256 validationData)
    {
        bytes32 hash = userOpHash.toEthSignedMessageHash();
        if (owner != ECDSA.recover(hash, userOp.signature)) {
            return SIG_VALIDATION_FAILED;
        }
        return SIG_VALIDATION_SUCCESS;
    }
}
