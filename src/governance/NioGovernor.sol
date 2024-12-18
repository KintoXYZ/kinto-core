// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Governor} from "@openzeppelin-5.0.1/contracts/governance/Governor.sol";
import {GovernorSettings} from "@openzeppelin-5.0.1/contracts/governance/extensions/GovernorSettings.sol";
import {GovernorTimelockAccess} from "@openzeppelin-5.0.1/contracts/governance/extensions/GovernorTimelockAccess.sol";
import {GovernorStorage} from "@openzeppelin-5.0.1/contracts/governance/extensions/GovernorStorage.sol";
import {GovernorVotes} from "@openzeppelin-5.0.1/contracts/governance/extensions/GovernorVotes.sol";
import {GovernorCountingSimple} from "@openzeppelin-5.0.1/contracts/governance/extensions/GovernorCountingSimple.sol";
import {IVotes} from "@openzeppelin-5.0.1/contracts/governance/utils/IVotes.sol";

/**
 * @title NioGovernor
 * @notice Governance contract for the Kinto DAO, managed by Nio Guardians
 */
contract NioGovernor is
    Governor,
    GovernorSettings,
    GovernorCountingSimple,
    GovernorStorage,
    GovernorVotes,
    GovernorTimelockAccess
{
    /**
     * @notice Initializes the NioGovernor contract
     * @param token The address of the token used for voting
     * @param manager The address of the timelock manager
     */
    constructor(IVotes token, address manager)
        Governor("NioGovernor")
        GovernorSettings(3 days, 5 days, 1)
        GovernorVotes(token)
        GovernorTimelockAccess(manager, 3 days)
    {}

    /**
     * @notice Calculates the quorum required for a proposal to pass
     * @return The quorum count (5 Nios out of 9)
     */
    function quorum(uint256) public pure override returns (uint256) {
        return 5;
    }

    /**
     * @notice Returns the voting delay
     * @return The voting delay in seconds
     */
    function votingDelay() public view override(Governor, GovernorSettings) returns (uint256) {
        return super.votingDelay();
    }

    /**
     * @notice Returns the voting period
     * @return The voting period in seconds
     */
    function votingPeriod() public view override(Governor, GovernorSettings) returns (uint256) {
        return super.votingPeriod();
    }

    /**
     * @notice Checks if a proposal needs queuing
     * @param proposalId The ID of the proposal
     * @return True if the proposal needs queuing, false otherwise
     */
    function proposalNeedsQueuing(uint256 proposalId)
        public
        view
        virtual
        override(Governor, GovernorTimelockAccess)
        returns (bool)
    {
        return super.proposalNeedsQueuing(proposalId);
    }

    /**
     * @notice Returns the proposal threshold
     * @return The number of votes required to create a proposal
     */
    function proposalThreshold() public view override(Governor, GovernorSettings) returns (uint256) {
        return super.proposalThreshold();
    }

    /**
     * @notice Creates a new proposal
     * @param targets The addresses of the contracts to call
     * @param values The amounts of ETH to send with each call
     * @param calldatas The call data for each contract call
     * @param description A description of the proposal
     * @return The ID of the newly created proposal
     */
    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) public override(Governor, GovernorTimelockAccess) returns (uint256) {
        return super.propose(targets, values, calldatas, description);
    }

    /**
     * @notice Internal function to create a new proposal
     * @param targets The addresses of the contracts to call
     * @param values The amounts of ETH to send with each call
     * @param calldatas The call data for each contract call
     * @param description A description of the proposal
     * @param proposer The address of the proposer
     * @return The ID of the newly created proposal
     */
    function _propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description,
        address proposer
    ) internal override(Governor, GovernorStorage) returns (uint256) {
        return super._propose(targets, values, calldatas, description, proposer);
    }

    /**
     * @notice Queues operations for a proposal
     * @param proposalId The ID of the proposal
     * @param targets The addresses of the contracts to call
     * @param values The amounts of ETH to send with each call
     * @param calldatas The call data for each contract call
     * @param descriptionHash The hash of the proposal's description
     * @return The timestamp at which the proposal will be ready for execution
     */
    function _queueOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockAccess) returns (uint48) {
        return super._queueOperations(proposalId, targets, values, calldatas, descriptionHash);
    }

    /**
     * @notice Executes the operations of a proposal
     * @param proposalId The ID of the proposal
     * @param targets The addresses of the contracts to call
     * @param values The amounts of ETH to send with each call
     * @param calldatas The call data for each contract call
     * @param descriptionHash The hash of the proposal's description
     */
    function _executeOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockAccess) {
        super._executeOperations(proposalId, targets, values, calldatas, descriptionHash);
    }

    /**
     * @notice Cancels a proposal
     * @param targets The addresses of the contracts to call
     * @param values The amounts of ETH to send with each call
     * @param calldatas The call data for each contract call
     * @param descriptionHash The hash of the proposal's description
     * @return The ID of the cancelled proposal
     */
    function _cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockAccess) returns (uint256) {
        return super._cancel(targets, values, calldatas, descriptionHash);
    }
}
