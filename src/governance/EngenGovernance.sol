// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/governance/Governor.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorCountingSimple.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorVotes.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorVotesQuorumFraction.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";

/**
 * @title EngenGovernance
 * @dev Implementation of the Governor contract for Engen Governance.
 *      This governance will be used to boostrap the Kinto Network.
 *      Chosen for simplicity, as it does not require a timelock.
 */
contract EngenGovernance is Governor, GovernorCountingSimple, GovernorVotes, GovernorVotesQuorumFraction {
    constructor(IVotes _token) Governor("EngenGovernance") GovernorVotes(_token) GovernorVotesQuorumFraction(15) {}

    /**
     * @dev Returns the delay period for voting.
     */
    function votingDelay() public pure override returns (uint256) {
        return 1 days;
    }

    /**
     * @dev Returns the voting period.
     */
    function votingPeriod() public pure override returns (uint256) {
        return 3 weeks;
    }

    /**
     * @dev Returns the threshold needed to create a proposal
     */
    function proposalThreshold() public pure override returns (uint256) {
        return 5e18;
    }

    // The following functions are overrides required by Solidity.
    function quorum(uint256 blockNumber)
        public
        view
        override(IGovernor, GovernorVotesQuorumFraction)
        returns (uint256)
    {
        return super.quorum(blockNumber);
    }
}
