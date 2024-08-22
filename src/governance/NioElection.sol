// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {IERC721} from "@openzeppelin-5.0.1/contracts/token/ERC721/IERC721.sol";
import {IERC20} from "@openzeppelin-5.0.1/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin-5.0.1/contracts/access/Ownable.sol";

import {BridgedKinto} from "@kinto-core/tokens/bridged/BridgedKinto.sol";

contract NioElection is Ownable {
    /* ============ Struct ============ */

    struct Candidate {
        address addr;
        uint256 votes;
        bool isEligible;
    }

    struct Election {
        uint256 startTime;
        uint256 contenderSubmissionEndTime;
        uint256 nomineeSelectionEndTime;
        uint256 complianceProcessEndTime;
        uint256 memberElectionEndTime;
        uint256 seatsAvailable;
        mapping(address => Candidate) candidates;
        address[] candidateList;
        mapping(address => bool) hasVoted;
        bool hasStarted;
    }

    /* ============ Constants ============ */

    uint256 public constant ELECTION_DURATION = 30 days;
    uint256 public constant MIN_VOTE_PERCENTAGE = 5e15; // 0.5% in wei
    BridgedKinto public immutable kToken;
    IERC721 public immutable nioNFT;

    /* ============ State Variables ============ */

    Election public currentElection;

    /* ============ Events ============ */

    event ElectionStarted(uint256 startTime, uint256 seatsAvailable);
    event CandidateDeclared(address candidate);
    event NomineeSelected(address nominee, uint256 votes);
    event CandidateDisqualified(address candidate);
    event VoteCast(address voter, address candidate, uint256 weight);
    event ElectionCompleted(address[] winners);

    /* ============ Errors ============ */

    error ElectionAlreadyActive();
    error NoActiveElection();
    error ContenderSubmissionEnded();
    error CurrentNioCannotBeCandidate();
    error VotingNotStarted();
    error VotingEnded();
    error AlreadyVoted();
    error NoVotingPower();
    error InvalidCandidate();
    error NomineeSelectionNotEnded();
    error ComplianceProcessEnded();
    error ElectionPeriodNotEnded();

    /* ============ Constructor ============ */

    constructor(address _kToken, address _nioNFT) Ownable(msg.sender) {
        kToken = BridgedKinto(_kToken);
        nioNFT = IERC721(_nioNFT);
    }

    /* ============ External ============ */

    // TODO: Allow to start only if 6 months has passed over the past election or it is the first one
    function startElection(uint256 _seatsAvailable) external onlyOwner {
        if (currentElection.hasStarted) revert ElectionAlreadyActive();

        currentElection.startTime = block.timestamp;
        currentElection.contenderSubmissionEndTime = block.timestamp + 5 days;
        currentElection.nomineeSelectionEndTime = block.timestamp + 10 days;
        currentElection.complianceProcessEndTime = block.timestamp + 15 days;
        currentElection.memberElectionEndTime = block.timestamp + 30 days;
        currentElection.seatsAvailable = _seatsAvailable;
        currentElection.hasStarted = true;

        emit ElectionStarted(currentElection.startTime, _seatsAvailable);
    }

    function declareCandidate() external {
        if (!currentElection.hasStarted) revert NoActiveElection();
        if (block.timestamp > currentElection.contenderSubmissionEndTime) revert ContenderSubmissionEnded();
        if (isNio(msg.sender)) revert CurrentNioCannotBeCandidate();

        currentElection.candidates[msg.sender] = Candidate(msg.sender, 0, false);
        currentElection.candidateList.push(msg.sender);

        emit CandidateDeclared(msg.sender);
    }

    function vote(address _candidate) external {
        if (!currentElection.hasStarted) revert NoActiveElection();
        if (block.timestamp <= currentElection.contenderSubmissionEndTime) revert VotingNotStarted();
        if (block.timestamp > currentElection.memberElectionEndTime) revert VotingEnded();
        if (currentElection.hasVoted[msg.sender]) revert AlreadyVoted();

        uint256 voterBalance = kToken.balanceOf(msg.sender);
        if (voterBalance == 0) revert NoVotingPower();

        Candidate storage candidate = currentElection.candidates[_candidate];
        if (candidate.addr == address(0)) revert InvalidCandidate();

        uint256 weight = calculateVoteWeight();
        uint256 weightedVotes = voterBalance * weight / 1e18;

        candidate.votes = candidate.votes + weightedVotes;
        currentElection.hasVoted[msg.sender] = true;

        uint256 totalVotableTokens = kToken.getPastTotalSupply(currentElection.startTime);

        if (block.timestamp <= currentElection.nomineeSelectionEndTime) {
            if (candidate.votes >= totalVotableTokens * MIN_VOTE_PERCENTAGE / 1e18) {
                candidate.isEligible = true;
                emit NomineeSelected(_candidate, candidate.votes);
            }
        }

        emit VoteCast(msg.sender, _candidate, weightedVotes);
    }

    function disqualifyCandidate(address _candidate) external onlyOwner {
        if (!currentElection.hasStarted) revert NoActiveElection();
        if (block.timestamp <= currentElection.nomineeSelectionEndTime) revert NomineeSelectionNotEnded();
        if (block.timestamp > currentElection.complianceProcessEndTime) revert ComplianceProcessEnded();

        Candidate storage candidate = currentElection.candidates[_candidate];
        if (candidate.addr == address(0)) revert InvalidCandidate();

        candidate.isEligible = false;
        emit CandidateDisqualified(_candidate);
    }

    function completeElection() external onlyOwner {
        if (!currentElection.hasStarted) revert NoActiveElection();
        if (block.timestamp <= currentElection.memberElectionEndTime) revert ElectionPeriodNotEnded();

        address[] memory winners = new address[](currentElection.seatsAvailable);
        uint256 winnerCount = 0;

        for (
            uint256 i = 0; i < currentElection.candidateList.length && winnerCount < currentElection.seatsAvailable; i++
        ) {
            address candidateAddr = currentElection.candidateList[i];
            Candidate memory candidate = currentElection.candidates[candidateAddr];

            if (candidate.isEligible) {
                winners[winnerCount] = candidateAddr;
                winnerCount++;
            }
        }

        // TODO: Implement logic to mint Nio NFTs for winners

        currentElection.hasStarted = false;
        emit ElectionCompleted(winners);
    }

    /* ============ View ============ */

    function calculateVoteWeight() internal view returns (uint256) {
        if (block.timestamp <= currentElection.complianceProcessEndTime + 7 days) {
            return 1e18; // 100% weight
        } else {
            uint256 timeLeft = currentElection.memberElectionEndTime - block.timestamp;
            return timeLeft * 1e18 / 8 days; // Linear decrease from 100% to 0% over 8 days
        }
    }

    function isNio(address _address) internal view returns (bool) {
        return nioNFT.balanceOf(_address) > 0;
    }

    function getElectionStatus()
        external
        view
        returns (
            uint256 startTime,
            uint256 contenderSubmissionEndTime,
            uint256 nomineeSelectionEndTime,
            uint256 complianceProcessEndTime,
            uint256 memberElectionEndTime,
            uint256 seatsAvailable,
            bool hasStarted
        )
    {
        return (
            currentElection.startTime,
            currentElection.contenderSubmissionEndTime,
            currentElection.nomineeSelectionEndTime,
            currentElection.complianceProcessEndTime,
            currentElection.memberElectionEndTime,
            currentElection.seatsAvailable,
            currentElection.hasStarted
        );
    }

    function getCandidateInfo(address _candidate)
        external
        view
        returns (address addr, uint256 votes, bool isEligible)
    {
        Candidate memory candidate = currentElection.candidates[_candidate];
        return (candidate.addr, candidate.votes, candidate.isEligible);
    }
}
