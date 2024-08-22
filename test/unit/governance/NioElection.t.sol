// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC721} from "@openzeppelin-5.0.1/contracts/token/ERC721/IERC721.sol";
import {IERC20} from "@openzeppelin-5.0.1/contracts/token/ERC20/IERC20.sol";

import {NioElection} from "@kinto-core/governance/NioElection.sol";
import {NioGuardians} from "@kinto-core/tokens/NioGuardians.sol";
import {BridgedKinto} from "@kinto-core/tokens/bridged/BridgedKinto.sol";

import {SharedSetup} from "@kinto-core-test/SharedSetup.t.sol";

import "forge-std/console2.sol";

contract NiosElectionTest is SharedSetup {
    NioElection internal election;
    BridgedKinto internal kinto;
    NioGuardians internal nios;

    address public owner;
    address public user1;
    address public user2;
    address public user3;

    function setUp() public {
        kinto = BridgedKinto(payable(address(new UUPSProxy(address(new BridgedKinto()), ""))));
        nios = new NioGuardians(_owner);
        election = new NiosElection(address(kinto), address(nios));

        // Distribute tokens
        kToken.transfer(user1, 100000 * 10**18);
        kToken.transfer(user2, 100000 * 10**18);
        kToken.transfer(user3, 100000 * 10**18);

        // Mint NFT for user3 (current Nio)
        nioNFT.mint(user3, 1);
    }

    function testStartElection() public {
        election.startElection(5);
        (uint256 startTime, , , , , uint256 seatsAvailable, bool isActive) = election.getElectionStatus();
        assertEq(seatsAvailable, 5);
        assertEq(isActive, true);
        assertEq(startTime, block.timestamp);
    }

    function testCannotStartActiveElection() public {
        election.startElection(5);
        vm.expectRevert(abi.encodeWithSelector(NiosElection.ElectionAlreadyActive.selector));
        election.startElection(3);
    }

    function testDeclareCandidate() public {
        election.startElection(5);
        vm.prank(user1);
        election.declareCandidate();
        (address addr, , ) = election.getCandidateInfo(user1);
        assertEq(addr, user1);
    }

    function testCannotDeclareCandidateAfterDeadline() public {
        election.startElection(5);
        vm.warp(block.timestamp + 6 days);
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(NiosElection.ContenderSubmissionEnded.selector));
        election.declareCandidate();
    }

    function testCurrentNioCannotBeCandidate() public {
        election.startElection(5);
        vm.prank(user3);
        vm.expectRevert(abi.encodeWithSelector(NiosElection.CurrentNioCannotBeCandidate.selector));
        election.declareCandidate();
    }

    function testVoting() public {
        election.startElection(5);
        vm.prank(user1);
        election.declareCandidate();

        vm.warp(block.timestamp + 6 days);
        vm.prank(user2);
        election.vote(user1);

        (,uint256 votes,) = election.getCandidateInfo(user1);
        assertGt(votes, 0);
    }

    function testCannotVoteBeforeVotingStarts() public {
        election.startElection(5);
        vm.prank(user1);
        election.declareCandidate();

        vm.prank(user2);
        vm.expectRevert(abi.encodeWithSelector(NiosElection.VotingNotStarted.selector));
        election.vote(user1);
    }

    function testCannotVoteAfterVotingEnds() public {
        election.startElection(5);
        vm.prank(user1);
        election.declareCandidate();

        vm.warp(block.timestamp + 31 days);
        vm.prank(user2);
        vm.expectRevert(abi.encodeWithSelector(NiosElection.VotingEnded.selector));
        election.vote(user1);
    }

    function testCannotVoteTwice() public {
        election.startElection(5);
        vm.prank(user1);
        election.declareCandidate();

        vm.warp(block.timestamp + 6 days);
        vm.prank(user2);
        election.vote(user1);

        vm.prank(user2);
        vm.expectRevert(abi.encodeWithSelector(NiosElection.AlreadyVoted.selector));
        election.vote(user1);
    }

    function testDisqualifyCandidate() public {
        election.startElection(5);
        vm.prank(user1);
        election.declareCandidate();

        vm.warp(block.timestamp + 11 days);
        election.disqualifyCandidate(user1);

        (,,bool isEligible) = election.getCandidateInfo(user1);
        assertEq(isEligible, false);
    }

    function testCannotDisqualifyCandidateBeforeNomineeSelection() public {
        election.startElection(5);
        vm.prank(user1);
        election.declareCandidate();

        vm.warp(block.timestamp + 9 days);
        vm.expectRevert(abi.encodeWithSelector(NiosElection.NomineeSelectionNotEnded.selector));
        election.disqualifyCandidate(user1);
    }

    function testCannotDisqualifyCandidateAfterComplianceProcess() public {
        election.startElection(5);
        vm.prank(user1);
        election.declareCandidate();

        vm.warp(block.timestamp + 16 days);
        vm.expectRevert(abi.encodeWithSelector(NiosElection.ComplianceProcessEnded.selector));
        election.disqualifyCandidate(user1);
    }

    function testCompleteElection() public {
        election.startElection(5);
        vm.prank(user1);
        election.declareCandidate();
        vm.prank(user2);
        election.declareCandidate();

        vm.warp(block.timestamp + 6 days);
        vm.prank(user3);
        election.vote(user1);
        vm.prank(owner);
        election.vote(user2);

        vm.warp(block.timestamp + 25 days);
        election.completeElection();

        (,,,,,, bool isActive) = election.getElectionStatus();
        assertEq(isActive, false);
    }

    function testCannotCompleteElectionBeforeEnd() public {
        election.startElection(5);
        vm.warp(block.timestamp + 29 days);
        vm.expectRevert(abi.encodeWithSelector(NiosElection.ElectionPeriodNotEnded.selector));
        election.completeElection();
    }
}
