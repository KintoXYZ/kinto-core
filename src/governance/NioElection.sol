// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {IERC721} from "@openzeppelin-5.0.1/contracts/token/ERC721/IERC721.sol";
import {IERC20} from "@openzeppelin-5.0.1/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin-5.0.1/contracts/access/Ownable.sol";

import {BridgedKinto} from "@kinto-core/tokens/bridged/BridgedKinto.sol";
import {NioGuardians} from "@kinto-core/tokens/NioGuardians.sol";
import {IKintoID} from "@kinto-core/interfaces/IKintoID.sol";
import {IKintoWallet} from "@kinto-core/interfaces/IKintoWallet.sol";

import "forge-std/console2.sol";

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
        uint256 electionEndTime;
        mapping(address => Candidate) candidates;
        address[] candidateList;
        mapping(address => Nominee) nominees;
        address[] nomineeList;
        mapping(address => uint256) usedCandidateVotes;
        mapping(address => uint256) usedNomineeVotes;
        uint256 niosToElect;
        address[] electedNios;
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

    Election[] public elections;

    /* ============ Events ============ */

    event ElectionStarted(uint256 electionId, uint256 startTime, uint256 niosToElect);
    event CandidateSubmitted(uint256 electionId, address candidate);
    event NomineeSelected(uint256 electionId, address nominee, uint256 votes);
    event CandidateVoteCast(uint256 electionId, address voter, address candidate, uint256 weight);
    event NomineeVoteCast(uint256 electionId, address voter, address nominee, uint256 weight);
    event ElectionCompleted(uint256 electionId, address[] winners);

    /* ============ Errors ============ */

    error KYCRequired(address user);
    error ElectionAlreadyActive(uint256 electionId, uint256 startTime);
    error InvalidElectionPhase(uint256 electionId, ElectionPhase currentPhase, ElectionPhase requiredPhase);
    error ElectedNioCannotBeCandidate(address nio);
    error AlreadyVoted(address voter);
    error NoVotingPower(address voter);
    error InvalidCandidate(address candidate);
    error InvalidNominee(address nominee);
    error InsufficientEligibleCandidates(uint256 eligibleCount, uint256 required);
    error TooEarlyForNewElection(uint256 currentTime, uint256 nextElectionTime);
    error InvalidElectionId(uint256 electionId);

    /* ============ Constructor ============ */

    constructor(BridgedKinto _kToken, NioGuardians _nioNFT, IKintoID _kintoID) {
        kToken = _kToken;
        nioNFT = _nioNFT;
        kintoID = _kintoID;
    }

    /* ============ External Functions ============ */

    function startElection() external {
        if (isElectionActive()) {
            revert ElectionAlreadyActive(elections.length - 1, elections[elections.length - 1].startTime);
        }
        if (elections.length > 0) {
            uint256 lastElectionEndTime = elections[elections.length - 1].electionEndTime;
            if (block.timestamp < lastElectionEndTime + ELECTION_INTERVAL) {
                revert TooEarlyForNewElection(block.timestamp, lastElectionEndTime + ELECTION_INTERVAL);
            }
        }

        uint256 startTime = block.timestamp;
        elections.push();
        Election storage newElection = elections[elections.length - 1];
        newElection.startTime = startTime;
        newElection.candidateSubmissionEndTime = startTime + CANDIDATE_SUBMISSION_DURATION;
        newElection.candidateVotingEndTime = startTime + CANDIDATE_SUBMISSION_DURATION + CANDIDATE_VOTING_DURATION;
        newElection.complianceProcessEndTime =
            startTime + CANDIDATE_SUBMISSION_DURATION + CANDIDATE_VOTING_DURATION + COMPLIANCE_PROCESS_DURATION;
        newElection.nomineeVotingEndTime = startTime + ELECTION_DURATION;
        newElection.niosToElect = elections.length % 2 == 1 ? 4 : 5;

        emit ElectionStarted(elections.length - 1, startTime, newElection.niosToElect);
    }

    function submitCandidate() external {
        uint256 currentElectionId = elections.length - 1;
        ElectionPhase currentPhase = getCurrentPhase();
        if (currentPhase != ElectionPhase.CandidateSubmission) {
            revert InvalidElectionPhase(currentElectionId, currentPhase, ElectionPhase.CandidateSubmission);
        }
        if (isElectedNio(msg.sender)) revert ElectedNioCannotBeCandidate(msg.sender);

        Election storage election = elections[currentElectionId];
        election.candidates[msg.sender] = Candidate(msg.sender, 0);
        election.candidateList.push(msg.sender);

        emit CandidateSubmitted(currentElectionId, msg.sender);
    }

    function voteForCandidate(address _candidate, uint256 _votes) external {
        if (!kintoID.isKYC(IKintoWallet(_candidate).owners(0))) revert KYCRequired(_candidate);
        uint256 currentElectionId = getCurrentElectionId();
        ElectionPhase currentPhase = getCurrentPhase();
        if (currentPhase != ElectionPhase.CandidateVoting) {
            revert InvalidElectionPhase(currentElectionId, currentPhase, ElectionPhase.CandidateVoting);
        }

        Election storage election = elections[currentElectionId];
        uint256 availableVotes =
            kToken.getPastVotes(msg.sender, election.startTime) - election.usedCandidateVotes[msg.sender];

        if (_votes > availableVotes) revert NoVotingPower(msg.sender);

        Candidate storage candidate = election.candidates[_candidate];
        if (candidate.addr == address(0)) revert InvalidCandidate(_candidate);

        candidate.votes += _votes;
        election.usedCandidateVotes[msg.sender] += _votes;

        emit CandidateVoteCast(currentElectionId, msg.sender, _candidate, _votes);

        // Check if the candidate now meets the threshold to become a nominee
        uint256 totalVotableTokens = kToken.getPastTotalSupply(election.startTime);
        uint256 threshold = totalVotableTokens * MIN_VOTE_PERCENTAGE / 1e18;

        if (candidate.votes >= threshold && election.nominees[_candidate].addr == address(0)) {
            election.nominees[_candidate] = Nominee(_candidate, 0);
            election.nomineeList.push(_candidate);
            emit NomineeSelected(currentElectionId, _candidate, candidate.votes);
        }
    }

    function voteForNominee(address _nominee, uint256 _votes) external {
        if (!kintoID.isKYC(IKintoWallet(_nominee).owners(0))) revert KYCRequired(_nominee);
        uint256 currentElectionId = getCurrentElectionId();
        ElectionPhase currentPhase = getCurrentPhase();
        if (currentPhase != ElectionPhase.NomineeVoting) {
            revert InvalidElectionPhase(currentElectionId, currentPhase, ElectionPhase.NomineeVoting);
        }

        Election storage election = elections[currentElectionId];
        uint256 availableVotes =
            kToken.getPastVotes(msg.sender, election.startTime) - election.usedNomineeVotes[msg.sender];

        if (_votes > availableVotes) revert NoVotingPower(msg.sender);

        Nominee storage nominee = election.nominees[_nominee];
        if (nominee.addr == address(0)) revert InvalidNominee(_nominee);

        uint256 weight = calculateVoteWeight(currentElectionId);
        uint256 weightedVotes = _votes * weight / 1e18;

        nominee.votes += weightedVotes;
        election.usedNomineeVotes[msg.sender] += _votes;

        emit NomineeVoteCast(currentElectionId, msg.sender, _nominee, weightedVotes);
    }

    function electNios() external {
        uint256 currentElectionId = getCurrentElectionId();
        ElectionPhase currentPhase = getCurrentPhase();
        if (currentPhase != ElectionPhase.AwaitingElection) {
            revert InvalidElectionPhase(currentElectionId, currentPhase, ElectionPhase.AwaitingElection);
        }

        Election storage election = elections[currentElectionId];
        address[] memory sortedNominees = sortNomineesByVotes(currentElectionId);
        address[] memory winners = new address[](election.niosToElect);
        uint256 winnerCount = 0;

        for (uint256 i = 0; i < sortedNominees.length && winnerCount < election.niosToElect; i++) {
            winners[winnerCount] = sortedNominees[i];
            winnerCount++;
        }

        if (winnerCount < election.niosToElect) {
            revert InsufficientEligibleCandidates(winnerCount, election.niosToElect);
        }

        election.electedNios = winners;
        election.electionEndTime = block.timestamp;

        uint256 nftStartId = election.niosToElect == 4 ? 1 : 5;
        for (uint256 index = 0; index < winners.length; index++) {
            uint256 nftId = nftStartId + index;
            if (nioNFT.exists(nftId)) {
                nioNFT.burn(nftId);
            }
            nioNFT.mint(winners[index], nftId);
        }

        emit ElectionCompleted(currentElectionId, winners);
    }

    /* ============ Internal Functions ============ */

    function calculateVoteWeight(uint256 _electionId) internal view returns (uint256) {
        Election storage election = elections[_electionId];
        if (block.timestamp <= election.complianceProcessEndTime + 7 days) {
            return 1e18; // 100% weight
        } else {
            uint256 timeLeft = election.nomineeVotingEndTime - block.timestamp;
            return timeLeft * 1e18 / 8 days; // Linear decrease from 100% to 0% over 8 days
        }
    }

    function isElectedNio(address _address) internal view returns (bool) {
        if (elections.length == 0) {
            return false;
        }
        address[] memory currentNios = elections[elections.length - 1].electedNios;
        for (uint256 i = 0; i < currentNios.length; i++) {
            if (currentNios[i] == _address) {
                return true;
            }
        }
        return false;
    }

    function sortNomineesByVotes(uint256 _electionId) internal view returns (address[] memory) {
        Election storage election = elections[_electionId];
        uint256 length = election.nomineeList.length;
        address[] memory sortedNominees = new address[](length);
        uint256[] memory votes = new uint256[](length);

        // Initialize arrays
        for (uint256 i = 0; i < length; i++) {
            sortedNominees[i] = election.nomineeList[i];
            votes[i] = election.nominees[election.nomineeList[i]].votes;
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
        Election storage election = elections[elections.length - 1];

        if (block.timestamp < election.candidateSubmissionEndTime) {
            return ElectionPhase.CandidateSubmission;
        }
        if (block.timestamp < election.candidateVotingEndTime) {
            return ElectionPhase.CandidateVoting;
        }
        if (block.timestamp < election.complianceProcessEndTime) {
            return ElectionPhase.ComplianceProcess;
        }
        if (block.timestamp < election.nomineeVotingEndTime) {
            return ElectionPhase.NomineeVoting;
        }
        if (election.electionEndTime == 0) {
            return ElectionPhase.AwaitingElection;
        }
        return ElectionPhase.Completed;
    }

    function isElectionActive() public view returns (bool) {
        return elections.length > 0 && getCurrentPhase() != ElectionPhase.Completed;
    }

    function getNextElectionTime() external view returns (uint256) {
        if (elections.length == 0) {
            return block.timestamp;
        }
        uint256 lastElectionEndTime = elections[elections.length - 1].electionEndTime;
        return lastElectionEndTime + ELECTION_INTERVAL;
    }

    function getElectionCount() external view returns (uint256) {
        return elections.length;
    }

    function getCurrentElectionId() public view returns (uint256) {
        return elections.length - 1;
    }

    function getElectionDetails()
        external
        view
        returns (
            uint256 startTime,
            uint256 candidateSubmissionEndTime,
            uint256 candidateVotingEndTime,
            uint256 complianceProcessEndTime,
            uint256 nomineeVotingEndTime,
            uint256 electionEndTime,
            uint256 niosToElect
        )
    {
        return getElectionDetails(getCurrentElectionId());
    }

    /**
     * @dev Returns the details of a specific election.
     * @param electionId The ID of the election to query.
     * @return startTime The start time of the election.
     * @return candidateSubmissionEndTime The end time for candidate submissions.
     * @return candidateVotingEndTime The end time for candidate voting.
     * @return complianceProcessEndTime The end time for the compliance process.
     * @return nomineeVotingEndTime The end time for nominee voting.
     * @return electionEndTime The end time of the election.
     * @return niosToElect The number of Nios to be elected in this election.
     */
    function getElectionDetails(uint256 electionId)
        public
        view
        returns (
            uint256 startTime,
            uint256 candidateSubmissionEndTime,
            uint256 candidateVotingEndTime,
            uint256 complianceProcessEndTime,
            uint256 nomineeVotingEndTime,
            uint256 electionEndTime,
            uint256 niosToElect
        )
    {
        if (electionId >= elections.length) revert InvalidElectionId(electionId);
        Election storage election = elections[electionId];
        return (
            election.startTime,
            election.candidateSubmissionEndTime,
            election.candidateVotingEndTime,
            election.complianceProcessEndTime,
            election.nomineeVotingEndTime,
            election.electionEndTime,
            election.niosToElect
        );
    }

    function getCandidates() external view returns (address[] memory) {
        return getCandidates(getCurrentElectionId());
    }

    /**
     * @dev Returns the list of candidates for a specific election.
     * @param electionId The ID of the election to query.
     * @return An array of candidate addresses.
     */
    function getCandidates(uint256 electionId) public view returns (address[] memory) {
        if (electionId >= elections.length) revert InvalidElectionId(electionId);
        return elections[electionId].candidateList;
    }

    function getNominees() external view returns (address[] memory) {
        return getNominees(getCurrentElectionId());
    }

    /**
     * @dev Returns the list of nominees for a specific election.
     * @param electionId The ID of the election to query.
     * @return An array of nominee addresses.
     */
    function getNominees(uint256 electionId) public view returns (address[] memory) {
        if (electionId >= elections.length) revert InvalidElectionId(electionId);
        return elections[electionId].nomineeList;
    }

    function getCandidateVotes(address _candidate) external view returns (uint256) {
        return getCandidateVotes(getCurrentElectionId(), _candidate);
    }

    /**
     * @dev Returns the votes received by a candidate in a specific election.
     * @param electionId The ID of the election to query.
     * @param _candidate The address of the candidate.
     * @return The number of votes received by the candidate.
     */
    function getCandidateVotes(uint256 electionId, address _candidate) public view returns (uint256) {
        if (electionId >= elections.length) revert InvalidElectionId(electionId);
        return elections[electionId].candidates[_candidate].votes;
    }

    function getNomineeVotes(address _nominee) external view returns (uint256) {
        return getNomineeVotes(getCurrentElectionId(), _nominee);
    }

    /**
     * @dev Returns the votes received by a nominee in a specific election.
     * @param electionId The ID of the election to query.
     * @param _nominee The address of the nominee.
     * @return The number of votes received by the nominee.
     */
    function getNomineeVotes(uint256 electionId, address _nominee) public view returns (uint256) {
        if (electionId >= elections.length) revert InvalidElectionId(electionId);
        return elections[electionId].nominees[_nominee].votes;
    }

    function getElectedNios() external view returns (address[] memory) {
        return getElectedNios(getCurrentElectionId());
    }

    /**
     * @dev Returns the elected Nios for a completed election.
     * @param electionId The ID of the election to query.
     * @return An array of elected Nio addresses.
     */
    function getElectedNios(uint256 electionId) public view returns (address[] memory) {
        if (electionId >= elections.length) revert InvalidElectionId(electionId);
        return elections[electionId].electedNios;
    }

    function getUsedCandidateVotes(address _voter) external view returns (uint256) {
        return getUsedCandidateVotes(getCurrentElectionId(), _voter);
    }

    /**
     * @dev Returns the number of votes used by a voter in the candidate voting phase of a specific election.
     * @param electionId The ID of the election to query.
     * @param _voter The address of the voter.
     * @return The number of votes used by the voter in the candidate voting phase.
     */
    function getUsedCandidateVotes(uint256 electionId, address _voter) public view returns (uint256) {
        if (electionId >= elections.length) revert InvalidElectionId(electionId);
        return elections[electionId].usedCandidateVotes[_voter];
    }

    function getUsedNomineeVotes(address _voter) external view returns (uint256) {
        return getUsedNomineeVotes(getCurrentElectionId(), _voter);
    }
    /**
     * @dev Returns the number of votes used by a voter in the nominee voting phase of a specific election.
     * @param electionId The ID of the election to query.
     * @param _voter The address of the voter.
     * @return The number of votes used by the voter in the nominee voting phase.
     */

    function getUsedNomineeVotes(uint256 electionId, address _voter) public view returns (uint256) {
        if (electionId >= elections.length) revert InvalidElectionId(electionId);
        return elections[electionId].usedNomineeVotes[_voter];
    }
}
