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

        // Set up past election result to simulate current Nios
        address[] memory currentNios = new address[](1);
        currentNios[0] = eve;
        election.setPastElectionResult(0, currentNios);
    }

    function testStartElection() public {
        election.startElection();
        (uint256 startTime,,,,,, uint256 niosToElect) = election.getElectionStatus();
        assertEq(niosToElect, 4); // First election elects 4 Nios
        assertTrue(election.isElectionActive());
        assertEq(startTime, block.timestamp);
    }

    function testCannotStartActiveElection() public {
        election.startElection();
        vm.expectRevert(abi.encodeWithSelector(NioElection.ElectionAlreadyActive.selector));
        election.startElection();
    }

    function testCannotStartElectionTooEarly() public {
        election.startElection();
        vm.warp(block.timestamp + 31 days);
        election.completeElection();
        
        vm.warp(block.timestamp + 179 days); // Just before the ELECTION_INTERVAL
        vm.expectRevert(abi.encodeWithSelector(NioElection.TooEarlyForNewElection.selector));
        election.startElection();
    }

    function testAnyoneCanStartElection() public {
        election.startElection();
        vm.warp(block.timestamp + 31 days);
        election.completeElection();
        
        vm.warp(block.timestamp + 180 days);
        vm.prank(alice);
        election.startElection();
        assertTrue(election.isElectionActive());
    }

    function testDeclareCandidate() public {
        election.startElection();
        vm.prank(alice);
        election.declareCandidate();
        (address addr,,,) = election.getCandidateInfo(alice);
        assertEq(addr, alice);
    }

    function testCannotDeclareCandidateAfterDeadline() public {
        election.startElection();
        vm.warp(block.timestamp + 6 days);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(NioElection.InvalidElectionPhase.selector));
        election.declareCandidate();
    }

    function testCurrentNioCannotBeCandidate() public {
        election.startElection();
        vm.prank(eve);
        vm.expectRevert(abi.encodeWithSelector(NioElection.CurrentNioCannotBeCandidate.selector));
        election.declareCandidate();
    }

    function testVoteForNominee() public {
        election.startElection();
        vm.prank(alice);
        election.declareCandidate();

        vm.warp(block.timestamp + 6 days);
        vm.prank(bob);
        election.voteForNominee(alice);

        (,uint256 nomineeVotes,,) = election.getCandidateInfo(alice);
        assertGt(nomineeVotes, 0);
    }

    function testVoteForMember() public {
        election.startElection();
        vm.prank(alice);
        election.declareCandidate();

        // Make alice eligible
        vm.warp(block.timestamp + 6 days);
        vm.prank(bob);
        election.voteForNominee(alice);

        // Vote for member
        vm.warp(block.timestamp + 11 days);
        vm.prank(bob);
        election.voteForMember(alice);

        (,,uint256 electionVotes,) = election.getCandidateInfo(alice);
        assertGt(electionVotes, 0);
    }

    function testCannotVoteForNomineeBeforeNomineeSelection() public {
        election.startElection();
        vm.prank(alice);
        election.declareCandidate();

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(NioElection.InvalidElectionPhase.selector));
        election.voteForNominee(alice);
    }

    function testCannotVoteForMemberBeforeMemberElection() public {
        election.startElection();
        vm.prank(alice);
        election.declareCandidate();

        vm.warp(block.timestamp + 6 days);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(NioElection.InvalidElectionPhase.selector));
        election.voteForMember(alice);
    }

    function testCannotVoteTwice() public {
        election.startElection();
        vm.prank(alice);
        election.declareCandidate();

        vm.warp(block.timestamp + 6 days);
        vm.prank(bob);
        election.voteForNominee(alice);

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(NioElection.AlreadyVoted.selector));
        election.voteForNominee(alice);
    }

    function testDisqualifyCandidate() public {
        election.startElection();
        vm.prank(alice);
        election.declareCandidate();

        vm.warp(block.timestamp + 11 days);
        election.disqualifyCandidate(alice);

        (,,,bool isEligible) = election.getCandidateInfo(alice);
        assertEq(isEligible, false);
    }

    function testCannotDisqualifyCandidateBeforeComplianceProcess() public {
        election.startElection();
        vm.prank(alice);
        election.declareCandidate();

        vm.warp(block.timestamp + 9 days);
        vm.expectRevert(abi.encodeWithSelector(NioElection.InvalidElectionPhase.selector));
        election.disqualifyCandidate(alice);
    }

    function testCannotDisqualifyCandidateAfterComplianceProcess() public {
        election.startElection();
        vm.prank(alice);
        election.declareCandidate();

        vm.warp(block.timestamp + 16 days);
        vm.expectRevert(abi.encodeWithSelector(NioElection.InvalidElectionPhase.selector));
        election.disqualifyCandidate(alice);
    }

    function testCompleteElection() public {
        election.startElection();
        vm.prank(alice);
        election.declareCandidate();
        vm.prank(bob);
        election.declareCandidate();

        // Nominee voting
        vm.warp(block.timestamp + 6 days);
        vm.prank(eve);
        election.voteForNominee(alice);
        vm.prank(admin);
        election.voteForNominee(bob);

        // Member voting
        vm.warp(block.timestamp + 16 days);
        vm.prank(eve);
        election.voteForMember(alice);
        vm.prank(admin);
        election.voteForMember(bob);

        vm.warp(block.timestamp + 31 days);
        election.completeElection();

        assertFalse(election.isElectionActive());
        assertEq(election.electionCount(), 1);
    }

    function testCannotCompleteElectionBeforeEnd() public {
        election.startElection();
        vm.warp(block.timestamp + 29 days);
        vm.expectRevert(abi.encodeWithSelector(NioElection.InvalidElectionPhase.selector));
        election.completeElection();
    }

    function testAlternatingNiosToElect() public {
        // First election
        election.startElection();
        vm.warp(block.timestamp + 31 days);
        election.completeElection();
        (,,,,,, uint256 niosToElect) = election.getElectionStatus();
        assertEq(niosToElect, 4);

        // Second election
        vm.warp(block.timestamp + 180 days);
        election.startElection();
        (,,,,,, niosToElect) = election.getElectionStatus();
        assertEq(niosToElect, 5);
    }

    function testGetCurrentNios() public {
        address[] memory currentNios = election.getCurrentNios();
        assertEq(currentNios.length, 1);
        assertEq(currentNios[0], eve);
    }

    // Helper function to set past election result (for testing purposes only)
    function setPastElectionResult(uint256 _electionId, address[] memory _winners) public {
        election.setPastElectionResult(_electionId, _winners);
    }
}
