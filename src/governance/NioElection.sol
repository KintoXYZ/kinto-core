// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {IERC721} from "@openzeppelin-5.0.1/contracts/token/ERC721/IERC721.sol";
import {IERC20} from "@openzeppelin-5.0.1/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin-5.0.1/contracts/access/Ownable.sol";

import {BridgedKinto} from "@kinto-core/tokens/bridged/BridgedKinto.sol";
import {NioGuardians} from "@kinto-core/tokens/NioGuardians.sol";
import {IKintoID} from "@kinto-core/interfaces/IKintoID.sol";

contract NioElection {
    /* ============ Types ============ */

    enum ElectionPhase {
        NotStarted,
        CandidateSubmission,
        CandidateVoting,
        ComplianceProcess,
        NomineeVoting,
        AwaitingElection,
        Completed
    }

    struct Candidate {
        address addr;
        uint256 votes;
    }

    struct Nominee {
        address addr;
        uint256 votes;
    }

    struct Election {
        uint256 startTime;
        uint256 candidateSubmissionEndTime;
        uint256 candidateVotingEndTime;
        uint256 complianceProcessEndTime;
        uint256 nomineeVotingEndTime;
        mapping(address => Candidate) candidates;
        address[] candidateList;
        mapping(address => Nominee) nominees;
        address[] nomineeList;
        mapping(address => bool) hasVotedForCandidate;
        mapping(address => bool) hasVotedForNominee;
        uint256 niosToElect;
    }

    /* ============ Constants & Immutables ============ */

    uint256 public constant CANDIDATE_SUBMISSION_DURATION = 5 days;
    uint256 public constant CANDIDATE_VOTING_DURATION = 5 days;
    uint256 public constant COMPLIANCE_PROCESS_DURATION = 5 days;
    uint256 public constant NOMINEE_VOTING_DURATION = 15 days;
    uint256 public constant ELECTION_DURATION = 30 days;
    uint256 public constant MIN_VOTE_PERCENTAGE = 5e15; // 0.5% in wei
    uint256 public constant ELECTION_INTERVAL = 180 days; // 6 months

    BridgedKinto public immutable kToken;
    NioGuardians public immutable nioNFT;
    IKintoID public immutable kintoID;

    /* ============ State Variables ============ */

    Election public currentElection;
    uint256 public lastElectionEndTime;
    uint256 public electionCount;
    mapping(uint256 => address[]) public pastElectionResults;

    /* ============ Events ============ */

    event ElectionStarted(uint256 startTime, uint256 niosToElect);
    event CandidateSubmitted(address candidate);
    event NomineeSelected(address nominee, uint256 votes);
    event CandidateVoteCast(address voter, address candidate, uint256 weight);
    event NomineeVoteCast(address voter, address nominee, uint256 weight);
    event ElectionCompleted(uint256 electionId, address[] winners);

    /* ============ Errors ============ */

    error ElectionAlreadyActive(uint256 startTime);
    error InvalidElectionPhase(ElectionPhase currentPhase, ElectionPhase requiredPhase);
    error ElectedNioCannotBeCandidate(address nio);
    error AlreadyVoted(address voter);
    error NoVotingPower(address voter);
    error InvalidCandidate(address candidate);
    error InvalidNominee(address nominee);
    error InsufficientEligibleCandidates(uint256 eligibleCount, uint256 required);
    error TooEarlyForNewElection(uint256 currentTime, uint256 nextElectionTime);

    /* ============ Constructor ============ */

    constructor(BridgedKinto _kToken, NioGuardians _nioNFT, IKintoID _kintoID) {
        kToken = _kToken;
        nioNFT = _nioNFT;
        kintoID = _kintoID;
    }

    /* ============ External Functions ============ */

    function startElection() external {
        if (isElectionActive()) revert ElectionAlreadyActive(currentElection.startTime);
        if (block.timestamp < lastElectionEndTime + ELECTION_INTERVAL) {
            revert TooEarlyForNewElection(block.timestamp, lastElectionEndTime + ELECTION_INTERVAL);
        }

        uint256 startTime = block.timestamp;
        currentElection.startTime = startTime;
        currentElection.candidateSubmissionEndTime = startTime + CANDIDATE_SUBMISSION_DURATION;
        currentElection.candidateVotingEndTime = startTime + CANDIDATE_SUBMISSION_DURATION + CANDIDATE_VOTING_DURATION;
        currentElection.complianceProcessEndTime = startTime + CANDIDATE_SUBMISSION_DURATION + CANDIDATE_VOTING_DURATION + COMPLIANCE_PROCESS_DURATION;
        currentElection.nomineeVotingEndTime = startTime + ELECTION_DURATION;
        currentElection.niosToElect = electionCount % 2 == 0 ? 4 : 5;

        emit ElectionStarted(startTime, currentElection.niosToElect);
    }

    function submitCandidate() external {
        ElectionPhase currentPhase = getCurrentPhase();
        if (currentPhase != ElectionPhase.CandidateSubmission) {
            revert InvalidElectionPhase(currentPhase, ElectionPhase.CandidateSubmission);
        }
        if (isElectedNio(msg.sender)) revert ElectedNioCannotBeCandidate(msg.sender);

        currentElection.candidates[msg.sender] = Candidate(msg.sender, 0);
        currentElection.candidateList.push(msg.sender);

        emit CandidateSubmitted(msg.sender);
    }

    function voteForCandidate(address _candidate) external {
        ElectionPhase currentPhase = getCurrentPhase();
        if (currentPhase != ElectionPhase.CandidateVoting) {
            revert InvalidElectionPhase(currentPhase, ElectionPhase.CandidateVoting);
        }
        if (currentElection.hasVotedForCandidate[msg.sender]) revert AlreadyVoted(msg.sender);

        uint256 votes = kToken.getPastVotes(msg.sender, currentElection.startTime);
        if (votes == 0) revert NoVotingPower(msg.sender);

        Candidate storage candidate = currentElection.candidates[_candidate];
        if (candidate.addr == address(0)) revert InvalidCandidate(_candidate);

        candidate.votes += votes;
        currentElection.hasVotedForCandidate[msg.sender] = true;

        emit CandidateVoteCast(msg.sender, _candidate, votes);

        // Check if the candidate now meets the threshold to become a nominee
        uint256 totalVotableTokens = kToken.getPastTotalSupply(currentElection.startTime);
        uint256 threshold = totalVotableTokens * MIN_VOTE_PERCENTAGE / 1e18;

        if (candidate.votes >= threshold && currentElection.nominees[_candidate].addr == address(0)) {
            currentElection.nominees[_candidate] = Nominee(_candidate, 0);
            currentElection.nomineeList.push(_candidate);
            emit NomineeSelected(_candidate, candidate.votes);
        }
    }

    function voteForNominee(address _nominee) external {
        ElectionPhase currentPhase = getCurrentPhase();
        if (currentPhase != ElectionPhase.NomineeVoting) {
            revert InvalidElectionPhase(currentPhase, ElectionPhase.NomineeVoting);
        }
        if (currentElection.hasVotedForNominee[msg.sender]) revert AlreadyVoted(msg.sender);

        uint256 votes = kToken.getPastVotes(msg.sender, currentElection.startTime);
        if (votes == 0) revert NoVotingPower(msg.sender);

        Nominee storage nominee = currentElection.nominees[_nominee];
        if (nominee.addr == address(0)) revert InvalidNominee(_nominee);

        uint256 weight = calculateVoteWeight();
        uint256 weightedVotes = votes * weight / 1e18;

        nominee.votes += weightedVotes;
        currentElection.hasVotedForNominee[msg.sender] = true;

        emit NomineeVoteCast(msg.sender, _nominee, weightedVotes);
    }

    function electNios() external {
        ElectionPhase currentPhase = getCurrentPhase();
        if (currentPhase != ElectionPhase.Completed) revert InvalidElectionPhase(currentPhase, ElectionPhase.Completed);

        address[] memory sortedNominees = sortNomineesByVotes();
        address[] memory winners = new address[](currentElection.niosToElect);
        uint256 winnerCount = 0;

        for (uint256 i = 0; i < sortedNominees.length && winnerCount < currentElection.niosToElect; i++) {
            winners[winnerCount] = sortedNominees[i];
            winnerCount++;
        }

        if (winnerCount < currentElection.niosToElect) {
            revert InsufficientEligibleCandidates(winnerCount, currentElection.niosToElect);
        }

        // TODO: Implement logic to mint Nio NFTs for winners

        pastElectionResults[electionCount] = winners;
        lastElectionEndTime = block.timestamp;
        electionCount++;

        emit ElectionCompleted(electionCount - 1, winners);
    }

    /* ============ Internal Functions ============ */

    function calculateVoteWeight() internal view returns (uint256) {
        if (block.timestamp <= currentElection.complianceProcessEndTime + 7 days) {
            return 1e18; // 100% weight
        } else {
            uint256 timeLeft = currentElection.nomineeVotingEndTime - block.timestamp;
            return timeLeft * 1e18 / 8 days; // Linear decrease from 100% to 0% over 8 days
        }
    }

    function isElectedNio(address _address) internal view returns (bool) {
        if (electionCount == 0) {
            return false;
        }
        address[] memory currentNios = pastElectionResults[electionCount - 1];
        for (uint256 i = 0; i < currentNios.length; i++) {
            if (currentNios[i] == _address) {
                return true;
            }
        }
        return false;
    }

    function sortNomineesByVotes() internal view returns (address[] memory) {
        uint256 length = currentElection.nomineeList.length;
        address[] memory sortedNominees = new address[](length);
        uint256[] memory votes = new uint256[](length);

        // Initialize arrays
        for (uint256 i = 0; i < length; i++) {
            sortedNominees[i] = currentElection.nomineeList[i];
            votes[i] = currentElection.nominees[currentElection.nomineeList[i]].votes;
        }

        // Perform insertion sort
        for (uint256 i = 1; i < length; i++) {
            address key = sortedNominees[i];
            uint256 keyVotes = votes[i];
            int256 j = int256(i) - 1;

            while (j >= 0 && votes[uint256(j)] < keyVotes) {
                sortedNominees[uint256(j + 1)] = sortedNominees[uint256(j)];
                votes[uint256(j + 1)] = votes[uint256(j)];
                j--;
            }
            sortedNominees[uint256(j + 1)] = key;
            votes[uint256(j + 1)] = keyVotes;
        }

        return sortedNominees;
    }

    /* ============ View Functions ============ */

    function getCurrentPhase() public view returns (ElectionPhase) {
        if (currentElection.startTime == 0) {
            return ElectionPhase.NotStarted;
        }
        if (block.timestamp < currentElection.candidateSubmissionEndTime) {
            return ElectionPhase.CandidateSubmission;
        }
        if (block.timestamp < currentElection.candidateVotingEndTime) {
            return ElectionPhase.CandidateVoting;
        }
        if (block.timestamp < currentElection.complianceProcessEndTime) {
            return ElectionPhase.ComplianceProcess;
        }
        if (block.timestamp < currentElection.nomineeVotingEndTime) {
            return ElectionPhase.NomineeVoting;
        }
        if (lastElectionEndTime < currentElection.nomineeVotingEndTime) {
            return ElectionPhase.AwaitingElection;
        }
        return ElectionPhase.Completed;
    }

    function isElectionActive() public view returns (bool) {
        return currentElection.startTime != 0;
    }

    function getElectionStatus()
        external
        view
        returns (
            uint256 startTime,
            uint256 candidateSubmissionEndTime,
            uint256 candidateVotingEndTime,
            uint256 complianceProcessEndTime,
            uint256 nomineeVotingEndTime,
            ElectionPhase currentPhase,
            uint256 niosToElect
        )
    {
        return (
            currentElection.startTime,
            currentElection.candidateSubmissionEndTime,
            currentElection.candidateVotingEndTime,
            currentElection.complianceProcessEndTime,
            currentElection.nomineeVotingEndTime,
            getCurrentPhase(),
            currentElection.niosToElect
        );
    }

    function getCandidates() external view returns (address[] memory) {
        return currentElection.candidateList;
    }

    function getNominees() external view returns (address[] memory) {
        return currentElection.nomineeList;
    }

    function getCandidateInfo(address _candidate) external view returns (address addr, uint256 votes) {
        Candidate memory candidate = currentElection.candidates[_candidate];
        return (candidate.addr, candidate.votes);
    }

    function getNomineeInfo(address _nominee) external view returns (address addr, uint256 votes) {
        Nominee memory nominee = currentElection.nominees[_nominee];
        return (nominee.addr, nominee.votes);
    }

    function getPastElectionResult(uint256 _electionId) external view returns (address[] memory) {
        return pastElectionResults[_electionId];
    }

    function getNextElectionTime() external view returns (uint256) {
        return lastElectionEndTime + ELECTION_INTERVAL;
    }

    function getElectedNios() public view returns (address[] memory) {
        return electionCount == 0 ? new address[](0) : pastElectionResults[electionCount - 1];
    }
}
