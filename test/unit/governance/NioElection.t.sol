// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {IERC721} from "@openzeppelin-5.0.1/contracts/token/ERC721/IERC721.sol";
import {IERC20} from "@openzeppelin-5.0.1/contracts/token/ERC20/IERC20.sol";

import {NioElection} from "@kinto-core/governance/NioElection.sol";
import {NioGuardians} from "@kinto-core/tokens/NioGuardians.sol";
import {BridgedKinto} from "@kinto-core/tokens/bridged/BridgedKinto.sol";
import {UUPSProxy} from "@kinto-core-test/helpers/UUPSProxy.sol";

import {SharedSetup} from "@kinto-core-test/SharedSetup.t.sol";

import "forge-std/console2.sol";

contract NioElectionTest is SharedSetup {
    NioElection internal election;
    BridgedKinto internal kToken;
    NioGuardians internal nioNFT;

    uint256 public constant CANDIDATE_SUBMISSION_DURATION = 5 days;
    uint256 public constant CANDIDATE_VOTING_DURATION = 5 days;
    uint256 public constant COMPLIANCE_PROCESS_DURATION = 5 days;
    uint256 public constant NOMINEE_VOTING_DURATION = 15 days;
    uint256 public constant ELECTION_DURATION = 30 days;
    uint256 public constant MIN_VOTE_PERCENTAGE = 5e15; // 0.5% in wei
    uint256 public constant ELECTION_INTERVAL = 180 days; // 6 months

    function setUp() public override {
        super.setUp();

        kToken = BridgedKinto(payable(address(new UUPSProxy(address(new BridgedKinto()), ""))));
        kToken.initialize("KINTO TOKEN", "KINTO", admin, admin, admin);

        nioNFT = new NioGuardians(address(admin));
        election = new NioElection(kToken, nioNFT, _kintoID);
        vm.prank(admin);
        nioNFT.transferOwnership(address(election));

        // Distribute tokens and set up KYC
        uint256 kAmount = 100e18;
        for (uint256 i = 1; i < wallets.length; i++) {
            vm.prank(admin);
            kToken.mint(wallets[i], kAmount);
            vm.prank(wallets[i]);
            kToken.delegate(wallets[i]);
        }
    }

    function testStartElection() public {
        election.startElection();
        assertEq(uint256(election.getCurrentPhase()), uint256(NioElection.ElectionPhase.CandidateSubmission));
        (
            uint256 startTime,
            uint256 candidateSubmissionEndTime,
            uint256 candidateVotingEndTime,
            uint256 complianceProcessEndTime,
            uint256 nomineeVotingEndTime,
            uint256 electionEndTime,
            uint256 niosToElect
        ) = election.getElectionDetails(0);

        assertEq(startTime, block.timestamp);
        assertEq(candidateSubmissionEndTime, startTime + CANDIDATE_SUBMISSION_DURATION);
        assertEq(candidateVotingEndTime, candidateSubmissionEndTime + CANDIDATE_VOTING_DURATION);
        assertEq(complianceProcessEndTime, candidateVotingEndTime + COMPLIANCE_PROCESS_DURATION);
        assertEq(nomineeVotingEndTime, startTime + ELECTION_DURATION);
        assertEq(electionEndTime, 0); // Should be 0 before election is completed
        assertEq(niosToElect, 4); // First election should elect 4 Nios
    }

    function testStartElection_RevertWhenActiveElection() public {
        election.startElection();
        vm.expectRevert(abi.encodeWithSelector(NioElection.ElectionAlreadyActive.selector, 0, block.timestamp));
        election.startElection();
    }

    function testStartElection_RevertWhenElectionTooEarly() public {
        runElection();

        vm.warp(block.timestamp + 179 days); // Just before the ELECTION_INTERVAL
        uint256 nextElectionTime = election.getNextElectionTime();
        vm.expectRevert(
            abi.encodeWithSelector(NioElection.TooEarlyForNewElection.selector, block.timestamp, nextElectionTime)
        );
        election.startElection();
    }

    function testSubmitCandidate() public {
        election.startElection();

        vm.prank(alice);
        election.submitCandidate();

        address[] memory candidates = election.getCandidates(0);

        assertEq(candidates.length, 1);
        assertEq(candidates[0], alice);
    }

    function testSubmitCandidate_RevertWhenEAfterDeadline() public {
        election.startElection();
        vm.warp(block.timestamp + 6 days);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                NioElection.InvalidElectionPhase.selector,
                0,
                NioElection.ElectionPhase.CandidateVoting,
                NioElection.ElectionPhase.CandidateSubmission
            )
        );
        election.submitCandidate();
    }

    function testVoteForCandidate() public {
        election.startElection();
        vm.prank(alice);
        election.submitCandidate();
        vm.warp(block.timestamp + 6 days);

        vm.prank(bob);
        election.voteForCandidate(alice, 50e18);

        assertEq(election.getCandidateVotes(alice), 50e18);
    }

    function testVoteForNominee() public {
        election.startElection();

        vm.warp(block.timestamp + 16 days);
        vm.prank(bob);
        election.voteForNominee(alice, 50e18);
        assertGt(election.getNomineeVotes(0, alice), 0);
    }

    function testCannotVoteForCandidateBeforeCandidateVoting() public {
        election.startElection();
        vm.prank(alice);
        election.submitCandidate();
        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(
                NioElection.InvalidElectionPhase.selector,
                0,
                NioElection.ElectionPhase.CandidateSubmission,
                NioElection.ElectionPhase.CandidateVoting
            )
        );
        election.voteForCandidate(alice, 50e18);
    }

    function testCannotVoteForNomineeBeforeNomineeVoting() public {
        voteForNominees();

        vm.warp(block.timestamp + 11 days);
        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(
                NioElection.InvalidElectionPhase.selector,
                0,
                NioElection.ElectionPhase.ComplianceProcess,
                NioElection.ElectionPhase.NomineeVoting
            )
        );
        election.voteForNominee(alice, 50e18);
    }

    function testCannotVoteTwice() public {
        voteForNominees();

        vm.warp(block.timestamp + 16 days);
        vm.startPrank(bob);
        election.voteForNominee(alice, 50e18);
        vm.expectRevert(abi.encodeWithSelector(NioElection.NoVotingPower.selector, bob));
        election.voteForNominee(alice, 50e18);
        vm.stopPrank();
    }

    function testElectNios() public {
        voteForNominees();

        vm.warp(block.timestamp + 31 days);
        election.electNios();
        address[] memory electedNios = election.getElectedNios(0);
        assertEq(electedNios.length, 5);
    }

    function testCannotElectNiosBeforeEnd() public {
        voteForNominees();

        vm.warp(block.timestamp + 29 days);
        vm.expectRevert(
            abi.encodeWithSelector(
                NioElection.InvalidElectionPhase.selector,
                0,
                NioElection.ElectionPhase.NomineeVoting,
                NioElection.ElectionPhase.AwaitingElection
            )
        );
        election.electNios();
    }

    function testAlternatingNiosToElect() public {
        // First election
        runElection();
        (,,,,, uint256 electionEndTime, uint256 niosToElect) = election.getElectionDetails(0);
        assertEq(niosToElect, 4);

        // Second election
        vm.warp(electionEndTime + ELECTION_INTERVAL);
        runElection();
        (,,,,, electionEndTime, niosToElect) = election.getElectionDetails(1);
        assertEq(niosToElect, 5);

        // Third election
        vm.warp(electionEndTime + ELECTION_INTERVAL);
        runElection();
        (,,,,, electionEndTime, niosToElect) = election.getElectionDetails(2);
        assertEq(niosToElect, 4);
    }

    function testGetElectionDetails() public {
        election.startElection();
        (
            uint256 startTime,
            uint256 candidateSubmissionEndTime,
            uint256 candidateVotingEndTime,
            uint256 complianceProcessEndTime,
            uint256 nomineeVotingEndTime,
            uint256 electionEndTime,
            uint256 niosToElect
        ) = election.getElectionDetails(0);

        assertEq(startTime, block.timestamp);
        assertEq(candidateSubmissionEndTime, startTime + CANDIDATE_SUBMISSION_DURATION);
        assertEq(candidateVotingEndTime, candidateSubmissionEndTime + CANDIDATE_VOTING_DURATION);
        assertEq(complianceProcessEndTime, candidateVotingEndTime + COMPLIANCE_PROCESS_DURATION);
        assertEq(nomineeVotingEndTime, startTime + ELECTION_DURATION);
        assertEq(electionEndTime, 0); // Should be 0 before election is completed
        assertEq(niosToElect, 4);
    }

    function testVoteWeighting() public {
        voteForNominees();

        vm.warp(block.timestamp + 16 days);
        vm.prank(bob);
        election.voteForNominee(alice, 50e18);
        uint256 initialVotes = election.getNomineeVotes(0, alice);

        vm.warp(block.timestamp + 4 days);
        vm.prank(eve);
        election.voteForNominee(alice, 50e18);
        uint256 laterVotes = election.getNomineeVotes(0, alice) - initialVotes;

        assertGt(initialVotes, laterVotes);
    }

    // Helper functions
    function submitCandidates() internal {
        for (uint256 i = 1; i < wallets.length; i++) {
            vm.prank(wallets[i]);
            election.submitCandidate();
        }
    }

    function voteForCandidates() internal {
        for (uint256 i = 1; i < wallets.length; i++) {
            vm.prank(wallets[i]);
            election.voteForCandidate(wallets[i], 10e18);
        }
    }

    function voteForNominees() internal {
        for (uint256 i = 1; i < wallets.length; i++) {
            vm.prank(wallets[i]);
            election.voteForNominee(wallets[i], 10e18);
        }
    }

    function runElection() internal {
        election.startElection();
        submitCandidates();
        vm.warp(block.timestamp + CANDIDATE_SUBMISSION_DURATION);

        voteForCandidates();
        vm.warp(block.timestamp + CANDIDATE_VOTING_DURATION);
        vm.warp(block.timestamp + COMPLIANCE_PROCESS_DURATION);

        voteForNominees();
        vm.warp(block.timestamp + NOMINEE_VOTING_DURATION);

        election.electNios();
    }
}
