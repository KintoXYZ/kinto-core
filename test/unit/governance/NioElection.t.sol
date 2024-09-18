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

    uint256 internal kAmount = 100e18;
    uint256 internal fullVoteAmount = 100e18;
    uint256 internal halfVoteAmount = 50e18;

    function setUp() public override {
        super.setUp();

        kToken = BridgedKinto(payable(address(new UUPSProxy(address(new BridgedKinto()), ""))));
        kToken.initialize("KINTO TOKEN", "KINTO", admin, admin, admin);

        nioNFT = new NioGuardians(address(admin));
        election = new NioElection(kToken, nioNFT, _kintoID);
        vm.prank(admin);
        nioNFT.transferOwnership(address(election));

        // Distribute tokens and set up KYC
        for (uint256 i = 1; i < users.length; i++) {
            vm.prank(admin);
            kToken.mint(users[i], kAmount);
            vm.prank(users[i]);
            kToken.delegate(users[i]);
        }
    }

    /* ============ startElection ============ */

    function testStartElection() public {
        assertEq(election.getNextElectionTime(), block.timestamp);

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
        ) = election.getElectionDetails();

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

    /* ============ submitCandidate ============ */

    function testSubmitCandidate() public {
        election.startElection();

        vm.prank(alice);
        election.submitCandidate();

        address[] memory candidates = election.getCandidates();

        assertEq(candidates.length, 1);
        assertEq(candidates.length, election.getCandidates(0).length);
        assertEq(candidates[0], alice);
    }

    function testSubmitCandidate_RevertWhenAfterDeadline() public {
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

    function testSubmitCandidate_RevertWhenSubmitTwice() public {
        election.startElection();

        vm.prank(alice);
        election.submitCandidate();

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(NioElection.DuplicatedCandidate.selector, alice));
        election.submitCandidate();
    }

    /* ============ voteForCandidate ============ */

    function testVoteForCandidate() public {
        election.startElection();
        vm.prank(alice);
        election.submitCandidate();
        vm.warp(block.timestamp + 6 days);

        vm.prank(bob);
        election.voteForCandidate(alice, 50e18);

        address[] memory nominees = election.getNominees();
        assertEq(nominees.length, 1);
        assertEq(nominees.length, election.getNominees(0).length);
        assertEq(nominees[0], alice);

        assertEq(election.getCandidateVotes(alice), 50e18);
        assertEq(election.getUsedCandidateVotes(bob), 50e18);
        assertEq(election.getUsedCandidateVotes(0, bob), 50e18);
    }

    function testVoteForCandidate_RevertWhenNoKyc() public {
        election.startElection();

        vm.prank(alice);
        election.submitCandidate();

        revokeKYC(_kycProvider, alice0, alice0Pk);

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(NioElection.KYCRequired.selector, alice));
        election.voteForCandidate(alice, 50e18);
    }

    function testVoteForCandidate_RevertWhenBeforeCandidateVoting() public {
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

    function testVoteForCandidate_RevertWhenMaxNomineesReached() public {
        election.startElection();

        address[] memory signers = new address[](26);
        uint256[] memory signersPk = new uint256[](26);
        address[] memory users = new address[](26);
        for (uint256 i = 0; i < signers.length; i++) {
            (signers[i], signersPk[i]) = makeAddrAndKey(vm.toString(i));
            approveKYC(_kycProvider, signers[i], signersPk[i]);
            _kintoID.isKYC(signers[i]);
            vm.prank(signers[i]);
            users[i] = address(_walletFactory.createAccount(signers[i], _recoverer, 0));
        }

        // Distribute tokens and set up KYC
        for (uint256 i = 1; i < users.length; i++) {
            vm.prank(admin);
            kToken.mint(users[i], kAmount);
            vm.prank(users[i]);
            kToken.delegate(users[i]);
        }

        // Submit all candidates
        for (uint256 i = 1; i < users.length; i++) {
            vm.prank(users[i]);
            election.submitCandidate();
        }

        vm.warp(block.timestamp + CANDIDATE_SUBMISSION_DURATION);

        // Vote for the first 25 candidates to make them nominees
        for (uint256 i = 1; i < 25; i++) {
            vm.prank(users[i]);
            election.voteForCandidate(users[i], halfVoteAmount);
        }
        // Try to vote for the 26th candidate, which should revert
        vm.expectRevert(abi.encodeWithSelector(NioElection.MaxNomineesReached.selector));
        vm.prank(users[25]);
        election.voteForCandidate(users[25], halfVoteAmount);
    }

    /* ============ voteForNominee ============ */

    function testVoteForNominee() public {
        election.startElection();
        submitCandidates();
        vm.warp(block.timestamp + CANDIDATE_SUBMISSION_DURATION);
        voteForCandidates();
        vm.warp(block.timestamp + CANDIDATE_VOTING_DURATION);
        vm.warp(block.timestamp + COMPLIANCE_PROCESS_DURATION);

        vm.prank(bob);
        election.voteForNominee(alice, fullVoteAmount);

        assertEq(election.getNomineeVotes(alice), fullVoteAmount);

        assertEq(election.getUsedNomineeVotes(bob), fullVoteAmount);
        assertEq(election.getUsedNomineeVotes(0, bob), fullVoteAmount);
    }

    function testVoteForNominee_RevertWhenNoKyc() public {
        election.startElection();
        submitCandidates();
        vm.warp(block.timestamp + CANDIDATE_SUBMISSION_DURATION);
        voteForCandidates();
        vm.warp(block.timestamp + CANDIDATE_VOTING_DURATION);
        vm.warp(block.timestamp + COMPLIANCE_PROCESS_DURATION);

        revokeKYC(_kycProvider, alice0, alice0Pk);

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(NioElection.KYCRequired.selector, alice));
        election.voteForNominee(alice, fullVoteAmount);
    }

    function testVoteForNominee_RevertWhenBeforeNomineeVoting() public {
        election.startElection();
        submitCandidates();
        vm.warp(block.timestamp + CANDIDATE_SUBMISSION_DURATION);
        voteForCandidates();
        vm.warp(block.timestamp + CANDIDATE_VOTING_DURATION);

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

    function testVoteForNominee_RevertWhenVoteTwice() public {
        election.startElection();
        submitCandidates();
        vm.warp(block.timestamp + CANDIDATE_SUBMISSION_DURATION);
        voteForCandidates();
        vm.warp(block.timestamp + CANDIDATE_VOTING_DURATION);
        vm.warp(block.timestamp + COMPLIANCE_PROCESS_DURATION);

        vm.prank(bob);
        election.voteForNominee(alice, fullVoteAmount);

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(NioElection.NoVotingPower.selector, bob));
        election.voteForNominee(alice, fullVoteAmount);
    }

    function testVoteForNomineeVoteWeighting() public {
        election.startElection();
        submitCandidates();
        vm.warp(block.timestamp + CANDIDATE_SUBMISSION_DURATION);
        voteForCandidates();
        vm.warp(block.timestamp + CANDIDATE_VOTING_DURATION);
        vm.warp(block.timestamp + COMPLIANCE_PROCESS_DURATION);

        // 50% voting power
        vm.warp(block.timestamp + 11 days);
        vm.prank(bob);
        election.voteForNominee(alice, fullVoteAmount);

        assertEq(election.getNomineeVotes(alice), fullVoteAmount / 2);

        // ~0% voting power
        vm.warp(block.timestamp + 4 days - 1);
        vm.prank(eve);
        election.voteForNominee(alice, fullVoteAmount);

        uint256 weight = uint256(1e18) / 8 days;
        assertEq(election.getNomineeVotes(alice), fullVoteAmount / 2 + fullVoteAmount * weight / 1e18);
    }

    /* ============ electNios ============ */

    function testElectNios() public {
        assertFalse(election.isElectedNio(users[1]));

        runElection();

        (,,,,, uint256 electionEndTime,) = election.getElectionDetails();

        address[] memory electedNios = election.getElectedNios();
        assertEq(electedNios.length, 4);

        for (uint256 index = 0; index < electedNios.length; index++) {
            assertTrue(nioNFT.balanceOf(electedNios[index]) > 0);
        }
        for (uint256 index = 5; index < users.length; index++) {
            assertTrue(nioNFT.balanceOf(users[index]) == 0);
        }

        assertEq(electionEndTime, block.timestamp);
        assertEq(election.getElectionCount(), 1);
        assertTrue(election.isElectedNio(users[1]));
    }

    function testElectNios_RevertWhenCandidateIsNio() public {
        runElection();

        // Second election
        (,,,,, uint256 electionEndTime,) = election.getElectionDetails();

        vm.warp(electionEndTime + ELECTION_INTERVAL);

        election.startElection();
        vm.prank(users[1]);
        vm.expectRevert(abi.encodeWithSelector(NioElection.ElectedNioCannotBeCandidate.selector, users[1]));
        election.submitCandidate();
    }

    function testElectNios_WhenLessWinnersThanRequired() public {
        assertFalse(election.isElectedNio(users[1]));

        election.startElection();
        submitCandidates();
        vm.warp(block.timestamp + CANDIDATE_SUBMISSION_DURATION);

        vm.warp(block.timestamp + CANDIDATE_VOTING_DURATION);
        vm.warp(block.timestamp + COMPLIANCE_PROCESS_DURATION);

        vm.warp(block.timestamp + NOMINEE_VOTING_DURATION);

        election.electNios();

        (,,,,, uint256 electionEndTime,) = election.getElectionDetails();

        address[] memory electedNios = election.getElectedNios();
        assertEq(electedNios.length, 0);

        assertEq(electionEndTime, block.timestamp);
        assertEq(election.getElectionCount(), 1);
        assertFalse(election.isElectedNio(users[1]));

        vm.warp(election.getNextElectionTime());

        election.startElection();
        submitCandidates();
        vm.warp(block.timestamp + CANDIDATE_SUBMISSION_DURATION);

        for (uint256 i = 1; i < 3; i++) {
            vm.prank(users[i]);
            election.voteForCandidate(users[i], halfVoteAmount);
        }
        vm.warp(block.timestamp + CANDIDATE_VOTING_DURATION);
        vm.warp(block.timestamp + COMPLIANCE_PROCESS_DURATION);

        vm.warp(block.timestamp + NOMINEE_VOTING_DURATION);

        election.electNios();

        (,,,,, electionEndTime,) = election.getElectionDetails();

        electedNios = election.getElectedNios();
        assertEq(electedNios.length, 2);

        for (uint256 index = 0; index < electedNios.length; index++) {
            assertTrue(nioNFT.balanceOf(electedNios[index]) > 0);
        }
        for (uint256 index = 3; index < users.length; index++) {
            assertTrue(nioNFT.balanceOf(users[index]) == 0);
        }

        assertEq(electionEndTime, block.timestamp);
        assertEq(election.getElectionCount(), 2);
        assertTrue(election.isElectedNio(users[1]));
        assertTrue(election.isElectedNio(users[2]));
        assertFalse(election.isElectedNio(users[3]));
        assertFalse(election.isElectedNio(users[4]));
        assertFalse(election.isElectedNio(users[5]));
    }

    function testElectNiosSorting() public {
        election.startElection();
        submitCandidates();
        vm.warp(block.timestamp + CANDIDATE_SUBMISSION_DURATION);

        // Vote for candidates with different amounts
        vm.prank(alice);
        election.voteForCandidate(bob, 80e18);
        vm.prank(bob);
        election.voteForCandidate(charlie, 90e18);
        vm.prank(charlie);
        election.voteForCandidate(ian, 70e18);
        vm.prank(ian);
        election.voteForCandidate(eve, 60e18);
        vm.prank(eve);
        election.voteForCandidate(frank, 50e18);

        vm.warp(block.timestamp + CANDIDATE_VOTING_DURATION);
        vm.warp(block.timestamp + COMPLIANCE_PROCESS_DURATION);

        // Vote for nominees with different amounts
        vm.prank(alice);
        election.voteForNominee(bob, 80e18);
        vm.prank(bob);
        election.voteForNominee(charlie, 90e18);
        vm.prank(charlie);
        election.voteForNominee(ian, 10e18);
        vm.prank(ian);
        election.voteForNominee(eve, 60e18);
        vm.prank(eve);
        election.voteForNominee(frank, 70e18);

        vm.warp(block.timestamp + NOMINEE_VOTING_DURATION);

        election.electNios();

        address[] memory electedNios = election.getElectedNios();

        // Check that we have the correct number of elected Nios
        assertEq(electedNios.length, 4);

        // Check that the elected Nios are in the correct order (highest votes to lowest)
        assertEq(electedNios[0], charlie);
        assertEq(electedNios[1], bob);
        assertEq(electedNios[2], frank);
        assertEq(electedNios[3], eve);

        // Verify vote counts
        assertEq(election.getNomineeVotes(charlie), 90e18);
        assertEq(election.getNomineeVotes(bob), 80e18);
        assertEq(election.getNomineeVotes(frank), 70e18);
        assertEq(election.getNomineeVotes(eve), 60e18);

        // Verify that frank (lowest votes) was not elected
        assertEq(election.getNomineeVotes(ian), 10e18);
    }

    function testElectNios_RevertWhenBeforeEnd() public {
        election.startElection();
        submitCandidates();
        vm.warp(block.timestamp + CANDIDATE_SUBMISSION_DURATION);
        voteForCandidates();
        vm.warp(block.timestamp + CANDIDATE_VOTING_DURATION);
        vm.warp(block.timestamp + COMPLIANCE_PROCESS_DURATION);

        vm.prank(bob);
        election.voteForNominee(alice, fullVoteAmount);

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
        (,,,,, uint256 electionEndTime, uint256 niosToElect) = election.getElectionDetails();
        assertEq(niosToElect, 4);

        // Second election
        vm.warp(electionEndTime + ELECTION_INTERVAL);

        election.startElection();
        for (uint256 i = 5; i < users.length; i++) {
            vm.prank(users[i]);
            election.submitCandidate();
        }
        vm.warp(block.timestamp + CANDIDATE_SUBMISSION_DURATION);

        for (uint256 i = 5; i < users.length; i++) {
            vm.prank(users[i]);
            election.voteForCandidate(users[i], halfVoteAmount);
        }
        vm.warp(block.timestamp + CANDIDATE_VOTING_DURATION);
        vm.warp(block.timestamp + COMPLIANCE_PROCESS_DURATION);

        for (uint256 i = 5; i < users.length; i++) {
            vm.prank(users[i]);
            election.voteForNominee(users[i], halfVoteAmount);
        }
        vm.warp(block.timestamp + NOMINEE_VOTING_DURATION);

        election.electNios();

        (,,,,, electionEndTime, niosToElect) = election.getElectionDetails(1);
        assertEq(niosToElect, 5);

        // Third election
        vm.warp(electionEndTime + ELECTION_INTERVAL);

        election.startElection();
        for (uint256 i = 1; i < 5; i++) {
            vm.prank(users[i]);
            election.submitCandidate();
        }
        vm.warp(block.timestamp + CANDIDATE_SUBMISSION_DURATION);

        for (uint256 i = 1; i < 5; i++) {
            vm.prank(users[i]);
            election.voteForCandidate(users[i], halfVoteAmount);
        }
        vm.warp(block.timestamp + CANDIDATE_VOTING_DURATION);
        vm.warp(block.timestamp + COMPLIANCE_PROCESS_DURATION);

        for (uint256 i = 1; i < 5; i++) {
            vm.prank(users[i]);
            election.voteForNominee(users[i], halfVoteAmount);
        }
        vm.warp(block.timestamp + NOMINEE_VOTING_DURATION);

        election.electNios();

        (,,,,, electionEndTime, niosToElect) = election.getElectionDetails(2);
        assertEq(niosToElect, 4);
    }

    /* ============ Helper functions ============ */

    function submitCandidates() internal {
        for (uint256 i = 1; i < users.length; i++) {
            vm.prank(users[i]);
            election.submitCandidate();
        }
    }

    function voteForCandidates() internal {
        for (uint256 i = 1; i < users.length; i++) {
            vm.prank(users[i]);
            election.voteForCandidate(users[i], halfVoteAmount);
        }
    }

    function voteForNominees() internal {
        for (uint256 i = 1; i < users.length; i++) {
            vm.prank(users[i]);
            election.voteForNominee(users[i], halfVoteAmount);
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
