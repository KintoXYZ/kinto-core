// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {IERC721} from "@openzeppelin-5.0.1/contracts/token/ERC721/IERC721.sol";
import {IERC20} from "@openzeppelin-5.0.1/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin-5.0.1/contracts/access/Ownable.sol";
import {Initializable} from "@openzeppelin-5.0.1/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin-5.0.1/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin-5.0.1/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {BridgedKinto} from "@kinto-core/tokens/bridged/BridgedKinto.sol";
import {NioGuardians} from "@kinto-core/tokens/NioGuardians.sol";
import {IKintoID} from "@kinto-core/interfaces/IKintoID.sol";
import {IKintoWallet} from "@kinto-core/interfaces/IKintoWallet.sol";

import "forge-std/console2.sol";

/**
 * @title NioElection
 * @notice This contract manages the election process for Nio Guardians in the Kinto ecosystem.
 * It handles candidate submission, voting, and the final election of Nios.
 */
contract NioElection is Initializable, UUPSUpgradeable, OwnableUpgradeable {
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
    uint256 public constant ELECTION_DURATION = 30 days;
    uint256 public constant MIN_VOTE_PERCENTAGE = 5e15; // 0.5% in wei
    uint256 public constant ELECTION_INTERVAL = 180 days; // 6 months
    uint256 public constant MAX_NOMINEES = 25; // New constant for maximum number of nominees

    BridgedKinto public immutable kToken;
    NioGuardians public immutable nioNFT;
    IKintoID public immutable kintoID;

    /* ============ State Variables ============ */

    Election[] public elections;

    /* ============ Events ============ */

    event ElectionStarted(uint256 electionId, uint256 startTime, uint256 niosToElect);
    event CandidateSubmitted(uint256 electionId, address candidate);
    event NomineeSelected(uint256 electionId, address nominee, uint256 votes);
    event CandidateVoteCast(uint256 electionId, address voter, address candidate, uint256 votes);
    event NomineeVoteCast(uint256 electionId, address voter, address nominee, uint256 votes);
    event ElectionCompleted(uint256 electionId, address[] winners);

    /* ============ Errors ============ */

    error KYCRequired(address user);
    error ElectionAlreadyActive(uint256 electionId, uint256 startTime);
    error InvalidElectionPhase(uint256 electionId, ElectionPhase currentPhase, ElectionPhase requiredPhase);
    error ElectedNioCannotBeCandidate(address nio);
    error DuplicatedCandidate(address candidate);
    error AlreadyVoted(address voter);
    error NoVotingPower(address voter);
    error InvalidCandidate(address candidate);
    error InvalidNominee(address nominee);
    error TooEarlyForNewElection(uint256 currentTime, uint256 nextElectionTime);
    error InvalidElectionId(uint256 electionId);
    error MaxNomineesReached();

    /* ============ Constructor ============ */

    /**
     * @notice Initializes the NioElection contract with necessary dependencies.
     * @param _kToken The address of the BridgedKinto token contract.
     * @param _nioNFT The address of the NioGuardians NFT contract.
     * @param _kintoID The address of the KintoID contract.
     */
    constructor(BridgedKinto _kToken, NioGuardians _nioNFT, IKintoID _kintoID) {
        kToken = _kToken;
        nioNFT = _nioNFT;
        kintoID = _kintoID;
    }

    /// @dev initialize the proxy
    function initialize(address owner) external virtual initializer {
        __UUPSUpgradeable_init();
        __Ownable_init(owner);
    }

    /**
     * @notice Authorize the upgrade. Only by an owner.
     * @param newImplementation address of the new implementation
     */
    // This function is called by the proxy contract when the factory is upgraded
    function _authorizeUpgrade(address newImplementation) internal view override onlyOwner {}

    /* ============ External Functions ============ */

    /**
     * @notice Initiates a new election cycle if the conditions are met.
     */
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
        // slither-disable-next-line weak-prng
        newElection.niosToElect = elections.length % 2 == 1 ? 4 : 5;

        emit ElectionStarted(elections.length - 1, startTime, newElection.niosToElect);
    }

    /**
     * @notice Allows a user to submit themselves as a candidate for the current election.
     */
    function submitCandidate() external {
        uint256 currentElectionId = elections.length - 1;
        ElectionPhase currentPhase = getCurrentPhase();
        if (currentPhase != ElectionPhase.CandidateSubmission) {
            revert InvalidElectionPhase(currentElectionId, currentPhase, ElectionPhase.CandidateSubmission);
        }
        if (!isEligibleForElection(msg.sender)) revert ElectedNioCannotBeCandidate(msg.sender);

        Election storage election = elections[currentElectionId];
        if (election.candidates[msg.sender].addr != address(0)) revert DuplicatedCandidate(msg.sender);

        election.candidates[msg.sender] = Candidate(msg.sender, 0);
        election.candidateList.push(msg.sender);

        emit CandidateSubmitted(currentElectionId, msg.sender);
    }

    /**
     * @notice Allows a user to vote for a candidate during the candidate voting phase.
     * @param candidate The address of the candidate to vote for.
     * @param votes The number of votes to cast.
     */
    function voteForCandidate(address candidate, uint256 votes) external {
        if (!kintoID.isKYC(IKintoWallet(candidate).owners(0))) revert KYCRequired(candidate);
        uint256 currentElectionId = getCurrentElectionId();
        ElectionPhase currentPhase = getCurrentPhase();
        if (currentPhase != ElectionPhase.CandidateVoting) {
            revert InvalidElectionPhase(currentElectionId, currentPhase, ElectionPhase.CandidateVoting);
        }

        Election storage election = elections[currentElectionId];
        uint256 availableVotes =
            kToken.getPastVotes(msg.sender, election.startTime) - election.usedCandidateVotes[msg.sender];

        if (votes > availableVotes) revert NoVotingPower(msg.sender);

        Candidate storage $candidate = election.candidates[candidate];
        if ($candidate.addr == address(0)) revert InvalidCandidate(candidate);

        $candidate.votes += votes;
        election.usedCandidateVotes[msg.sender] += votes;

        emit CandidateVoteCast(currentElectionId, msg.sender, candidate, votes);

        // Check if the candidate now meets the threshold to become a nominee
        uint256 totalVotableTokens = kToken.getPastTotalSupply(election.startTime);
        uint256 threshold = totalVotableTokens * MIN_VOTE_PERCENTAGE / 1e18;

        if ($candidate.votes >= threshold && election.nominees[candidate].addr == address(0)) {
            if (election.nomineeList.length >= (MAX_NOMINEES - 1)) revert MaxNomineesReached();
            election.nominees[candidate] = Nominee(candidate, 0);
            election.nomineeList.push(candidate);
            emit NomineeSelected(currentElectionId, candidate, $candidate.votes);
        }
    }

    /**
     * @notice Allows a user to vote for a $nominee during the $nominee voting phase.
     * @param nominee The address of the $nominee to vote for.
     * @param votes The number of votes to cast.
     */
    function voteForNominee(address nominee, uint256 votes) external {
        if (!kintoID.isKYC(IKintoWallet(nominee).owners(0))) revert KYCRequired(nominee);
        uint256 currentElectionId = getCurrentElectionId();
        ElectionPhase currentPhase = getCurrentPhase();
        if (currentPhase != ElectionPhase.NomineeVoting) {
            revert InvalidElectionPhase(currentElectionId, currentPhase, ElectionPhase.NomineeVoting);
        }

        Election storage election = elections[currentElectionId];
        uint256 availableVotes =
            kToken.getPastVotes(msg.sender, election.startTime) - election.usedNomineeVotes[msg.sender];

        if (votes > availableVotes) revert NoVotingPower(msg.sender);

        Nominee storage $nominee = election.nominees[nominee];
        if ($nominee.addr == address(0)) revert InvalidNominee(nominee);

        uint256 weight = calculateVoteWeight(currentElectionId);
        uint256 weightedVotes = votes * weight / 1e18;

        $nominee.votes += weightedVotes;
        election.usedNomineeVotes[msg.sender] += votes;

        emit NomineeVoteCast(currentElectionId, msg.sender, nominee, weightedVotes);
    }

    /**
     * @notice Finalizes the election by selecting the winners and minting Nio NFTs.
     */
    function electNios() external {
        uint256 currentElectionId = getCurrentElectionId();
        ElectionPhase currentPhase = getCurrentPhase();
        if (currentPhase != ElectionPhase.AwaitingElection) {
            revert InvalidElectionPhase(currentElectionId, currentPhase, ElectionPhase.AwaitingElection);
        }

        Election storage election = elections[currentElectionId];
        address[] memory sortedNominees = sortNomineesByVotes(currentElectionId);
        uint256 winnerCount = 0;

        for (uint256 i = 0; i < sortedNominees.length && winnerCount < election.niosToElect; i++) {
            election.electedNios.push(sortedNominees[i]);
            winnerCount++;
        }

        election.electionEndTime = block.timestamp;

        uint256 nftStartId = election.niosToElect == 4 ? 1 : 5;
        for (uint256 index = 0; index < winnerCount; index++) {
            uint256 nftId = nftStartId + index;
            if (nioNFT.exists(nftId)) {
                nioNFT.burn(nftId);
            }
            nioNFT.mint(election.electedNios[index], nftId);
        }

        emit ElectionCompleted(currentElectionId, election.electedNios);
    }

    /* ============ Internal Functions ============ */

    /**
     * @notice Calculates the weight of a vote based on the current time in the voting period.
     * @dev Internal function used to adjust vote weight over time.
     * @param _electionId The ID of the current election.
     * @return The calculated vote weight.
     */
    function calculateVoteWeight(uint256 _electionId) internal view returns (uint256) {
        Election storage election = elections[_electionId];
        if (block.timestamp <= election.complianceProcessEndTime + 7 days) {
            return 1e18; // 100% weight
        } else {
            uint256 timeLeft = election.nomineeVotingEndTime - block.timestamp;
            return timeLeft * 1e18 / 8 days; // Linear decrease from 100% to 0% over 8 days
        }
    }

    /**
     * @notice Sorts nominees by their vote count in descending order.
     * @dev Internal function used to determine election winners.
     * @param _electionId The ID of the election to sort nominees for.
     * @return An array of $nominee addresses sorted by votes.
     */
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

    /**
     * @notice Checks if an address is currently an elected Nio.
     * @param addr The address to check.
     * @return A boolean indicating whether the address is an elected Nio.
     */
    function isEligibleForElection(address addr) public view returns (bool) {
        uint256 currentElectionId = getCurrentElectionId();
        address[] memory nios = getElectedNios(currentElectionId);
        // if Nios not elected yet, look for previous election
        if (nios.length == 0 && currentElectionId > 0) {
            nios = getElectedNios(currentElectionId - 1);
        }
        for (uint256 index = 0; index < nios.length; index++) {
            if (nios[index] == addr) {
                return false;
            }
        }
        return true;
    }

    /**
     * @notice Checks if an address is currently an elected Nio.
     * @param addr The address to check.
     * @return A boolean indicating whether the address is an elected Nio.
     */
    function isElectedNio(address addr) public view returns (bool) {
        return nioNFT.balanceOf(addr) > 0;
    }

    /**
     * @notice Returns the current phase of the ongoing election.
     * @return The current ElectionPhase.
     */
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

    /**
     * @notice Checks if there is an active election.
     * @return A boolean indicating whether an election is currently active.
     */
    function isElectionActive() public view returns (bool) {
        return elections.length > 0 && getCurrentPhase() != ElectionPhase.Completed;
    }

    /**
     * @notice Calculates the timestamp for the next possible election.
     * @return The timestamp when the next election can be started.
     */
    function getNextElectionTime() external view returns (uint256) {
        if (elections.length == 0) {
            return block.timestamp;
        }
        uint256 lastElectionEndTime = elections[elections.length - 1].electionEndTime;
        return lastElectionEndTime + ELECTION_INTERVAL;
    }

    /**
     * @notice Returns the total number of elections that have been held.
     * @return The count of all elections.
     */
    function getElectionCount() external view returns (uint256) {
        return elections.length;
    }

    /**
     * @notice Returns the ID of the current or most recent election.
     * @return The current election ID.
     */
    function getCurrentElectionId() public view returns (uint256) {
        return elections.length - 1;
    }

    /**
     * @notice Retrieves the details of the current election.
     * @return startTime The start time of the election.
     * @return candidateSubmissionEndTime The end time for candidate submissions.
     * @return candidateVotingEndTime The end time for candidate voting.
     * @return complianceProcessEndTime The end time for the compliance process.
     * @return nomineeVotingEndTime The end time for $nominee voting.
     * @return electionEndTime The end time of the election.
     * @return niosToElect The number of Nios to be elected in this election.
     */
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
     * @notice Retrieves the details of a specific election.
     * @param electionId The ID of the election to query.
     * @return startTime The start time of the election.
     * @return candidateSubmissionEndTime The end time for candidate submissions.
     * @return candidateVotingEndTime The end time for candidate voting.
     * @return complianceProcessEndTime The end time for the compliance process.
     * @return nomineeVotingEndTime The end time for $nominee voting.
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

    /**
     * @notice Returns the list of candidates for the current election.
     * @return An array of candidate addresses.
     */
    function getCandidates() external view returns (address[] memory) {
        return getCandidates(getCurrentElectionId());
    }

    /**
     * @notice Returns the list of candidates for a specific election.
     * @param electionId The ID of the election to query.
     * @return An array of candidate addresses.
     */
    function getCandidates(uint256 electionId) public view returns (address[] memory) {
        if (electionId >= elections.length) revert InvalidElectionId(electionId);
        return elections[electionId].candidateList;
    }

    /**
     * @notice Returns the list of nominees for the current election.
     * @return An array of $nominee addresses.
     */
    function getNominees() external view returns (address[] memory) {
        return getNominees(getCurrentElectionId());
    }

    /**
     * @notice Returns the list of nominees for a specific election.
     * @param electionId The ID of the election to query.
     * @return An array of $nominee addresses.
     */
    function getNominees(uint256 electionId) public view returns (address[] memory) {
        if (electionId >= elections.length) revert InvalidElectionId(electionId);
        return elections[electionId].nomineeList;
    }

    /**
     * @notice Returns the votes received by a candidate in the current election.
     * @param candidate The address of the candidate.
     * @return The number of votes received by the candidate.
     */
    function getCandidateVotes(address candidate) external view returns (uint256) {
        return getCandidateVotes(getCurrentElectionId(), candidate);
    }

    /**
     * @notice Returns the votes received by a candidate in a specific election.
     * @param electionId The ID of the election to query.
     * @param candidate The address of the candidate.
     * @return The number of votes received by the candidate.
     */
    function getCandidateVotes(uint256 electionId, address candidate) public view returns (uint256) {
        if (electionId >= elections.length) revert InvalidElectionId(electionId);
        return elections[electionId].candidates[candidate].votes;
    }

    /**
     * @notice Returns the votes received by a $nominee in the current election.
     * @param nominee The address of the $nominee.
     * @return The number of votes received by the $nominee.
     */
    function getNomineeVotes(address nominee) external view returns (uint256) {
        return getNomineeVotes(getCurrentElectionId(), nominee);
    }

    /**
     * @notice Returns the votes received by a $nominee in a specific election.
     * @param electionId The ID of the election to query.
     * @param nominee The address of the $nominee.
     * @return The number of votes received by the $nominee.
     */
    function getNomineeVotes(uint256 electionId, address nominee) public view returns (uint256) {
        if (electionId >= elections.length) revert InvalidElectionId(electionId);
        return elections[electionId].nominees[nominee].votes;
    }

    /**
     * @notice Returns the elected Nios for the current election.
     * @return An array of elected Nio addresses.
     */
    function getElectedNios() external view returns (address[] memory) {
        return getElectedNios(getCurrentElectionId());
    }

    /**
     * @notice Returns the elected Nios for a completed election.
     * @param electionId The ID of the election to query.
     * @return An array of elected Nio addresses.
     */
    function getElectedNios(uint256 electionId) public view returns (address[] memory) {
        if (electionId >= elections.length) revert InvalidElectionId(electionId);
        return elections[electionId].electedNios;
    }

    /**
     * @notice Returns the number of votes used by a voter in the candidate voting phase of the current election.
     * @param _voter The address of the voter.
     * @return The number of votes used by the voter in the candidate voting phase.
     */
    function getUsedCandidateVotes(address _voter) external view returns (uint256) {
        return getUsedCandidateVotes(getCurrentElectionId(), _voter);
    }

    /**
     * @notice Returns the number of votes used by a voter in the candidate voting phase of a specific election.
     * @param electionId The ID of the election to query.
     * @param _voter The address of the voter.
     * @return The number of votes used by the voter in the candidate voting phase.
     */
    function getUsedCandidateVotes(uint256 electionId, address _voter) public view returns (uint256) {
        if (electionId >= elections.length) revert InvalidElectionId(electionId);
        return elections[electionId].usedCandidateVotes[_voter];
    }

    /**
     * @notice Returns the number of votes used by a voter in the $nominee voting phase of the current election.
     * @param _voter The address of the voter.
     * @return The number of votes used by the voter in the $nominee voting phase.
     */
    function getUsedNomineeVotes(address _voter) external view returns (uint256) {
        return getUsedNomineeVotes(getCurrentElectionId(), _voter);
    }

    /**
     * @notice Returns the number of votes used by a voter in the $nominee voting phase of a specific election.
     * @param electionId The ID of the election to query.
     * @param _voter The address of the voter.
     * @return The number of votes used by the voter in the $nominee voting phase.
     */
    function getUsedNomineeVotes(uint256 electionId, address _voter) public view returns (uint256) {
        if (electionId >= elections.length) revert InvalidElectionId(electionId);
        return elections[electionId].usedNomineeVotes[_voter];
    }
}
