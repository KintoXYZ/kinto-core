// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {IERC721} from "@openzeppelin-5.0.1/contracts/token/ERC721/IERC721.sol";
import {IERC20} from "@openzeppelin-5.0.1/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin-5.0.1/contracts/access/Ownable.sol";

import {BridgedKinto} from "@kinto-core/tokens/bridged/BridgedKinto.sol";

contract NioElection {
    /* ============ Types ============ */

    enum ElectionPhase {
        NotStarted,
        ContenderSubmission,
        NomineeSelection,
        ComplianceProcess,
        MemberElection,
        Completed
    }

    struct Candidate {
        address addr;
        uint256 nomineeVotes;
        uint256 electionVotes;
        bool isEligible;
    }

    struct Election {
        uint256 startTime;
        uint256 contenderSubmissionEndTime;
        uint256 nomineeSelectionEndTime;
        uint256 complianceProcessEndTime;
        uint256 memberElectionEndTime;
        mapping(address => Candidate) candidates;
        address[] candidateList;
        mapping(address => bool) hasVotedForNominee;
        mapping(address => bool) hasVotedForMember;
        bool isCompleted;
        uint256 niosToElect;
    }

    /* ============ Constants ============ */

    uint256 public constant CONTENDER_SUBMISSION_DURATION = 5 days;
    uint256 public constant NOMINEE_SELECTION_DURATION = 5 days;
    uint256 public constant COMPLIANCE_PROCESS_DURATION = 5 days;
    uint256 public constant MEMBER_ELECTION_DURATION = 15 days;
    uint256 public constant ELECTION_DURATION = 30 days;
    uint256 public constant MIN_VOTE_PERCENTAGE = 5e15; // 0.5% in wei
    uint256 public constant ELECTION_INTERVAL = 180 days; // 6 months

    BridgedKinto public immutable kToken;
    IERC721 public immutable nioNFT;

    /* ============ State Variables ============ */

    Election public currentElection;
    uint256 public lastElectionTime;
    uint256 public electionCount;
    mapping(uint256 => address[]) public pastElectionResults;

    /* ============ Events ============ */

    event ElectionStarted(uint256 startTime, uint256 niosToElect);
    event NomineeSubmitted(address candidate);
    event NomineeSelected(address nominee, uint256 votes);
    event NomineeVoteCast(address voter, address candidate, uint256 weight);
    event MemberVoteCast(address voter, address candidate, uint256 weight);
    event ElectionCompleted(uint256 electionId, address[] winners);

    /* ============ Errors ============ */

    error ElectionAlreadyActive(uint256 startTime);
    error ElectionNotActive();
    error InvalidElectionPhase(ElectionPhase currentPhase, ElectionPhase requiredPhase);
    error ElectedNioCannotBeCandidate(address nio);
    error AlreadyVoted(address voter);
    error NoVotingPower(address voter);
    error InvalidCandidate(address candidate);
    error InsufficientEligibleCandidates(uint256 eligibleCount, uint256 required);
    error TooEarlyForNewElection(uint256 currentTime, uint256 nextElectionTime);

    /* ============ Constructor ============ */

    constructor(address _kToken, address _nioNFT) {
        kToken = BridgedKinto(_kToken);
        nioNFT = IERC721(_nioNFT);
    }

    /* ============ External Functions ============ */

    function startElection() external {
        if (isElectionActive()) revert ElectionAlreadyActive(currentElection.startTime);
        if (block.timestamp < lastElectionTime + ELECTION_INTERVAL) {
            revert TooEarlyForNewElection(block.timestamp, lastElectionTime + ELECTION_INTERVAL);
        }

        uint256 startTime = block.timestamp;
        currentElection.startTime = startTime;
        currentElection.contenderSubmissionEndTime = startTime + CONTENDER_SUBMISSION_DURATION;
        currentElection.nomineeSelectionEndTime = startTime + CONTENDER_SUBMISSION_DURATION + NOMINEE_SELECTION_DURATION;
        currentElection.complianceProcessEndTime =
            startTime + CONTENDER_SUBMISSION_DURATION + NOMINEE_SELECTION_DURATION + COMPLIANCE_PROCESS_DURATION;
        currentElection.memberElectionEndTime = startTime + ELECTION_DURATION;
        currentElection.isCompleted = false;
        currentElection.niosToElect = electionCount % 2 == 0 ? 4 : 5;

        emit ElectionStarted(startTime, currentElection.niosToElect);
    }

    function submitNominee() external {
        ElectionPhase currentPhase = getCurrentPhase();
        if (currentPhase != ElectionPhase.ContenderSubmission) {
            revert InvalidElectionPhase(currentPhase, ElectionPhase.ContenderSubmission);
        }
        if (isElectedNio(msg.sender)) revert ElectedNioCannotBeCandidate(msg.sender);

        currentElection.candidates[msg.sender] = Candidate(msg.sender, 0, 0, false);
        currentElection.candidateList.push(msg.sender);

        emit NomineeSubmitted(msg.sender);
    }

    function voteForNominee(address _candidate) external {
        ElectionPhase currentPhase = getCurrentPhase();
        if (currentPhase != ElectionPhase.NomineeSelection) {
            revert InvalidElectionPhase(currentPhase, ElectionPhase.NomineeSelection);
        }
        if (currentElection.hasVotedForNominee[msg.sender]) revert AlreadyVoted(msg.sender);

        uint256 votes = kToken.getPastVotes(msg.sender, currentElection.startTime);
        if (votes == 0) revert NoVotingPower(msg.sender);

        Candidate storage candidate = currentElection.candidates[_candidate];
        if (candidate.addr == address(0)) revert InvalidCandidate(_candidate);

        candidate.nomineeVotes += votes;
        currentElection.hasVotedForNominee[msg.sender] = true;

        uint256 totalVotableTokens = kToken.getPastTotalSupply(currentElection.startTime);
        if (candidate.nomineeVotes >= totalVotableTokens * MIN_VOTE_PERCENTAGE / 1e18) {
            candidate.isEligible = true;
            emit NomineeSelected(_candidate, candidate.nomineeVotes);
        }

        emit NomineeVoteCast(msg.sender, _candidate, votes);
    }

    function voteForMember(address _candidate) external {
        ElectionPhase currentPhase = getCurrentPhase();
        if (currentPhase != ElectionPhase.MemberElection) {
            revert InvalidElectionPhase(currentPhase, ElectionPhase.MemberElection);
        }
        if (currentElection.hasVotedForMember[msg.sender]) revert AlreadyVoted(msg.sender);

        uint256 votes = kToken.getPastVotes(msg.sender, currentElection.startTime);
        if (votes == 0) revert NoVotingPower(msg.sender);

        Candidate storage candidate = currentElection.candidates[_candidate];
        if (candidate.addr == address(0) || !candidate.isEligible) revert InvalidCandidate(_candidate);

        uint256 weight = calculateVoteWeight();
        uint256 weightedVotes = votes * weight / 1e18;

        candidate.electionVotes += weightedVotes;
        currentElection.hasVotedForMember[msg.sender] = true;

        emit MemberVoteCast(msg.sender, _candidate, weightedVotes);
    }

    function completeElection() external {
        ElectionPhase currentPhase = getCurrentPhase();
        if (currentPhase != ElectionPhase.Completed) revert InvalidElectionPhase(currentPhase, ElectionPhase.Completed);
        if (currentElection.isCompleted) revert ElectionNotActive();

        address[] memory sortedCandidates = sortCandidatesByVotes();
        address[] memory winners = new address[](currentElection.niosToElect);
        uint256 winnerCount = 0;

        for (uint256 i = 0; i < sortedCandidates.length && winnerCount < currentElection.niosToElect; i++) {
            Candidate memory candidate = currentElection.candidates[sortedCandidates[i]];
            if (candidate.isEligible) {
                winners[winnerCount] = candidate.addr;
                winnerCount++;
            }
        }

        if (winnerCount < currentElection.niosToElect) {
            revert InsufficientEligibleCandidates(winnerCount, currentElection.niosToElect);
        }

        // TODO: Implement logic to mint Nio NFTs for winners

        currentElection.isCompleted = true;
        pastElectionResults[electionCount] = winners;
        lastElectionTime = block.timestamp;
        electionCount++;

        emit ElectionCompleted(electionCount - 1, winners);
    }

    /* ============ Internal Functions ============ */

    function calculateVoteWeight() internal view returns (uint256) {
        if (block.timestamp <= currentElection.complianceProcessEndTime + 7 days) {
            return 1e18; // 100% weight
        } else {
            uint256 timeLeft = currentElection.memberElectionEndTime - block.timestamp;
            return timeLeft * 1e18 / 8 days; // Linear decrease from 100% to 0% over 8 days
        }
    }

    function isElectedNio(address _address) internal view returns (bool) {
        if (electionCount == 0) {
            return false;
        }
        // For subsequent elections, check the past election results
        address[] memory currentNios = pastElectionResults[electionCount - 1];
        for (uint256 i = 0; i < currentNios.length; i++) {
            if (currentNios[i] == _address) {
                return true;
            }
        }
        return false;
    }

    function sortCandidatesByVotes() internal view returns (address[] memory) {
        // TODO: Use https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/Arrays.sol
        address[] memory sortedCandidates = currentElection.candidateList;
        uint256 length = sortedCandidates.length;

        for (uint256 i = 0; i < length - 1; i++) {
            for (uint256 j = 0; j < length - i - 1; j++) {
                if (
                    currentElection.candidates[sortedCandidates[j]].electionVotes
                        < currentElection.candidates[sortedCandidates[j + 1]].electionVotes
                ) {
                    (sortedCandidates[j], sortedCandidates[j + 1]) = (sortedCandidates[j + 1], sortedCandidates[j]);
                }
            }
        }

        return sortedCandidates;
    }

    /* ============ View Functions ============ */

    function getCurrentPhase() public view returns (ElectionPhase) {
        if (currentElection.startTime == 0 || currentElection.isCompleted) {
            return ElectionPhase.NotStarted;
        }
        if (block.timestamp < currentElection.contenderSubmissionEndTime) {
            return ElectionPhase.ContenderSubmission;
        }
        if (block.timestamp < currentElection.nomineeSelectionEndTime) {
            return ElectionPhase.NomineeSelection;
        }
        if (block.timestamp < currentElection.complianceProcessEndTime) {
            return ElectionPhase.ComplianceProcess;
        }
        if (block.timestamp < currentElection.memberElectionEndTime) {
            return ElectionPhase.MemberElection;
        }
        return ElectionPhase.Completed;
    }

    function isElectionActive() public view returns (bool) {
        return currentElection.startTime != 0 && !currentElection.isCompleted;
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
            ElectionPhase currentPhase,
            uint256 niosToElect
        )
    {
        return (
            currentElection.startTime,
            currentElection.contenderSubmissionEndTime,
            currentElection.nomineeSelectionEndTime,
            currentElection.complianceProcessEndTime,
            currentElection.memberElectionEndTime,
            getCurrentPhase(),
            currentElection.niosToElect
        );
    }

    function getCandidateInfo(address _candidate)
        external
        view
        returns (address addr, uint256 nomineeVotes, uint256 electionVotes, bool isEligible)
    {
        Candidate memory candidate = currentElection.candidates[_candidate];
        return (candidate.addr, candidate.nomineeVotes, candidate.electionVotes, candidate.isEligible);
    }

    function getPastElectionResult(uint256 _electionId) external view returns (address[] memory) {
        return pastElectionResults[_electionId];
    }

    function getNextElectionTime() external view returns (uint256) {
        return lastElectionTime + ELECTION_INTERVAL;
    }

    function getElectedNios() public view returns (address[] memory) {
        return electionCount == 0 ? new address[](0) : pastElectionResults[electionCount - 1];
    }
}
