// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC721} from "@openzeppelin-5.0.1/contracts/token/ERC721/IERC721.sol";
import {IERC20} from "@openzeppelin-5.0.1/contracts/token/ERC20/IERC20.sol";

import {NioElection} from "@kinto-core/governance/NioElection.sol";
import {NioGuardians} from "@kinto-core/tokens/NioGuardians.sol";
import {BridgedKinto} from "@kinto-core/tokens/bridged/BridgedKinto.sol";
import {UUPSProxy} from "@kinto-core-test/helpers/UUPSProxy.sol";

import {SharedSetup} from "@kinto-core-test/SharedSetup.t.sol";

import "forge-std/console2.sol";

contract NiosElectionTest is SharedSetup {
    NioElection internal election;
    BridgedKinto internal kToken;
    NioGuardians internal nioNFT;

    function setUp() public override {
        super.setUp();

        kToken = BridgedKinto(payable(address(new UUPSProxy(address(new BridgedKinto()), ""))));
        kToken.initialize("KINTO TOKEN", "KINTO", admin, admin, admin);

        nioNFT = new NioGuardians(admin);
        election = new NioElection(address(kToken), address(nioNFT));

        // Distribute tokens
        uint256 kAmount = 100_000e18;
        vm.startPrank(admin);
        kToken.mint(alice, kAmount);
        kToken.mint(bob, kAmount);
        kToken.mint(eve, kAmount);
        vm.stopPrank();

        // Mint NFT for eve (current Nio)
        vm.prank(admin);
        nioNFT.mint(eve, 1);
    }

    function testStartElection() public {
        election.startElection(5);
        (uint256 startTime,,,,, uint256 seatsAvailable, bool hasStarted) = election.getElectionStatus();
        assertEq(seatsAvailable, 5);
        assertEq(hasStarted, true);
        assertEq(startTime, block.timestamp);
    }

    function testCannotStartActiveElection() public {
        election.startElection(5);
        vm.expectRevert(abi.encodeWithSelector(NioElection.ElectionAlreadyActive.selector));
        election.startElection(3);
    }

    function testDeclareCandidate() public {
        election.startElection(5);
        vm.prank(alice);
        election.declareCandidate();
        (address addr,,) = election.getCandidateInfo(alice);
        assertEq(addr, alice);
    }

    function testCannotDeclareCandidateAfterDeadline() public {
        election.startElection(5);
        vm.warp(block.timestamp + 6 days);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(NioElection.ContenderSubmissionEnded.selector));
        election.declareCandidate();
    }

    function testCurrentNioCannotBeCandidate() public {
        election.startElection(5);
        vm.prank(eve);
        vm.expectRevert(abi.encodeWithSelector(NioElection.CurrentNioCannotBeCandidate.selector));
        election.declareCandidate();
    }

    function testVoting() public {
        election.startElection(5);
        vm.prank(alice);
        election.declareCandidate();

        vm.warp(block.timestamp + 6 days);
        vm.prank(bob);
        election.vote(alice);

        (, uint256 votes,) = election.getCandidateInfo(alice);
        assertGt(votes, 0);
    }

    function testCannotVoteBeforeVotingStarts() public {
        election.startElection(5);
        vm.prank(alice);
        election.declareCandidate();

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(NioElection.VotingNotStarted.selector));
        election.vote(alice);
    }

    function testCannotVoteAfterVotingEnds() public {
        election.startElection(5);
        vm.prank(alice);
        election.declareCandidate();

        vm.warp(block.timestamp + 31 days);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(NioElection.VotingEnded.selector));
        election.vote(alice);
    }

    function testCannotVoteTwice() public {
        election.startElection(5);
        vm.prank(alice);
        election.declareCandidate();

        vm.warp(block.timestamp + 6 days);
        vm.prank(bob);
        election.vote(alice);

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(NioElection.AlreadyVoted.selector));
        election.vote(alice);
    }

    function testDisqualifyCandidate() public {
        election.startElection(5);
        vm.prank(alice);
        election.declareCandidate();

        vm.warp(block.timestamp + 11 days);
        election.disqualifyCandidate(alice);

        (,, bool isEligible) = election.getCandidateInfo(alice);
        assertEq(isEligible, false);
    }

    function testCannotDisqualifyCandidateBeforeNomineeSelection() public {
        election.startElection(5);
        vm.prank(alice);
        election.declareCandidate();

        vm.warp(block.timestamp + 9 days);
        vm.expectRevert(abi.encodeWithSelector(NioElection.NomineeSelectionNotEnded.selector));
        election.disqualifyCandidate(alice);
    }

    function testCannotDisqualifyCandidateAfterComplianceProcess() public {
        election.startElection(5);
        vm.prank(alice);
        election.declareCandidate();

        vm.warp(block.timestamp + 16 days);
        vm.expectRevert(abi.encodeWithSelector(NioElection.ComplianceProcessEnded.selector));
        election.disqualifyCandidate(alice);
    }

    function testCompleteElection() public {
        election.startElection(5);
        vm.prank(alice);
        election.declareCandidate();
        vm.prank(bob);
        election.declareCandidate();

        vm.warp(block.timestamp + 6 days);
        vm.prank(eve);
        election.vote(alice);
        vm.prank(admin);
        election.vote(bob);

        vm.warp(block.timestamp + 25 days);
        election.completeElection();

        (,,,,,, bool hasStarted) = election.getElectionStatus();
        assertEq(hasStarted, false);
    }

    function testCannotCompleteElectionBeforeEnd() public {
        election.startElection(5);
        vm.warp(block.timestamp + 29 days);
        vm.expectRevert(abi.encodeWithSelector(NioElection.ElectionPeriodNotEnded.selector));
        election.completeElection();
    }
}
