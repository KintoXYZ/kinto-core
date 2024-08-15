// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Governor} from "@openzeppelin-5.0.1/contracts/governance/Governor.sol";
import {GovernorSettings} from "@openzeppelin-5.0.1/contracts/governance/extensions/GovernorSettings.sol";
import {GovernorTimelockAccess} from "@openzeppelin-5.0.1/contracts/governance/extensions/GovernorTimelockAccess.sol";
import {GovernorStorage} from "@openzeppelin-5.0.1/contracts/governance/extensions/GovernorStorage.sol";
import {GovernorVotes} from "@openzeppelin-5.0.1/contracts/governance/extensions/GovernorVotes.sol";
import {GovernorCountingSimple} from "@openzeppelin-5.0.1/contracts/governance/extensions/GovernorCountingSimple.sol";
import {IVotes} from "@openzeppelin-5.0.1/contracts/governance/utils/IVotes.sol";

contract NioGovernor is
    Governor,
    GovernorSettings,
    GovernorCountingSimple,
    GovernorStorage,
    GovernorVotes,
    GovernorTimelockAccess
{
    constructor(IVotes _token, address manager)
        Governor("NioGovernor")
        GovernorSettings(3 days, 5 days, 1)
        GovernorVotes(_token)
        GovernorTimelockAccess(manager, 3 days)
    {}

    function quorum(uint256) public pure override returns (uint256) {
        // Requires 5 Nios to vote out of 9
        return 5;
    }

    function votingDelay() public view override(Governor, GovernorSettings) returns (uint256) {
        return super.votingDelay();
    }

    function votingPeriod() public view override(Governor, GovernorSettings) returns (uint256) {
        return super.votingPeriod();
    }

    function proposalNeedsQueuing(uint256 proposalId)
        public
        view
        virtual
        override(Governor, GovernorTimelockAccess)
        returns (bool)
    {
        return super.proposalNeedsQueuing(proposalId);
    }

    function proposalThreshold() public view override(Governor, GovernorSettings) returns (uint256) {
        return super.proposalThreshold();
    }

    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) public override(Governor, GovernorTimelockAccess) returns (uint256) {
        return super.propose(targets, values, calldatas, description);
    }

    function _propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description,
        address proposer
    ) internal override(Governor, GovernorStorage) returns (uint256) {
        return super._propose(targets, values, calldatas, description, proposer);
    }

    function _queueOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockAccess) returns (uint48) {
        return super._queueOperations(proposalId, targets, values, calldatas, descriptionHash);
    }

    function _executeOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockAccess) {
        super._executeOperations(proposalId, targets, values, calldatas, descriptionHash);
    }

    function _cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockAccess) returns (uint256) {
        return super._cancel(targets, values, calldatas, descriptionHash);
    }
}
