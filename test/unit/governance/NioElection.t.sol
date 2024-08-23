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

    address internal nio0;
    address internal nio1;
    address internal nio2;
    address internal nio3;
    address internal nio4;
    address internal nio5;
    address internal nio6;
    address internal nio7;
    address internal nio8;
    address[] internal nios;

    function setUp() public override {
        super.setUp();

        nio0 = createUser("nio0");
        nio1 = createUser("nio1");
        nio2 = createUser("nio2");
        nio3 = createUser("nio3");
        nio4 = createUser("nio4");
        nio5 = createUser("nio5");
        nio6 = createUser("nio6");
        nio7 = createUser("nio7");
        nio8 = createUser("nio8");

        nios = [nio0, nio1, nio2, nio3, nio4, nio5, nio6, nio7, nio8];

        kToken = BridgedKinto(payable(address(new UUPSProxy(address(new BridgedKinto()), ""))));
        kToken.initialize("KINTO TOKEN", "KINTO", admin, admin, admin);

        nioNFT = new NioGuardians(admin);
        election = new NioElection(address(kToken), address(nioNFT));

        // Distribute tokens
        uint256 kAmount = 100_000e18;
        vm.startPrank(admin);
        for (uint256 i = 0; i < nios.length; i++) {
            kToken.mint(nios[i], kAmount);
        }
        kToken.mint(alice, kAmount);
        kToken.mint(bob, kAmount);
        kToken.mint(eve, kAmount);
        vm.stopPrank();

        // No initial Nios elected
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
        vm.expectRevert(abi.encodeWithSelector(NioElection.ElectionAlreadyActive.selector, block.timestamp));
        election.startElection();
    }

    function testCannotStartElectionTooEarly() public {
        election.startElection();
        vm.warp(block.timestamp + 31 days);
        election.completeElection();

        vm.warp(block.timestamp + 179 days); // Just before the ELECTION_INTERVAL
        uint256 nextElectionTime = election.getNextElectionTime();
        vm.expectRevert(
            abi.encodeWithSelector(NioElection.TooEarlyForNewElection.selector, block.timestamp, nextElectionTime)
        );
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
        vm.prank(nio0);
        election.declareCandidate();
        (address addr,,,) = election.getCandidateInfo(nio0);
        assertEq(addr, nio0);
    }

    function testCannotDeclareCandidateAfterDeadline() public {
        election.startElection();
        vm.warp(block.timestamp + 6 days);
        vm.prank(nio0);
        vm.expectRevert(
            abi.encodeWithSelector(
                NioElection.InvalidElectionPhase.selector,
                NioElection.ElectionPhase.NomineeSelection,
                NioElection.ElectionPhase.ContenderSubmission
            )
        );
        election.declareCandidate();
    }

    function testVoteForNominee() public {
        election.startElection();
        vm.prank(nio0);
        election.declareCandidate();

        vm.warp(block.timestamp + 6 days);
        vm.prank(nio1);
        election.voteForNominee(nio0);

        (, uint256 nomineeVotes,,) = election.getCandidateInfo(nio0);
        assertGt(nomineeVotes, 0);
    }

    function testVoteForMember() public {
        election.startElection();
        vm.prank(nio0);
        election.declareCandidate();

        // Make nio0 eligible
        vm.warp(block.timestamp + 6 days);
        vm.prank(nio1);
        election.voteForNominee(nio0);

        // Vote for member
        vm.warp(block.timestamp + 11 days);
        vm.prank(nio1);
        election.voteForMember(nio0);

        (,, uint256 electionVotes,) = election.getCandidateInfo(nio0);
        assertGt(electionVotes, 0);
    }

    function testCannotVoteForNomineeBeforeNomineeSelection() public {
        election.startElection();
        vm.prank(nio0);
        election.declareCandidate();

        vm.prank(nio1);
        vm.expectRevert(
            abi.encodeWithSelector(
                NioElection.InvalidElectionPhase.selector,
                NioElection.ElectionPhase.ContenderSubmission,
                NioElection.ElectionPhase.NomineeSelection
            )
        );
        election.voteForNominee(nio0);
    }

    function testCannotVoteForMemberBeforeMemberElection() public {
        election.startElection();
        vm.prank(nio0);
        election.declareCandidate();

        vm.warp(block.timestamp + 6 days);
        vm.prank(nio1);
        vm.expectRevert(
            abi.encodeWithSelector(
                NioElection.InvalidElectionPhase.selector,
                NioElection.ElectionPhase.NomineeSelection,
                NioElection.ElectionPhase.MemberElection
            )
        );
        election.voteForMember(nio0);
    }

    function testCannotVoteTwice() public {
        election.startElection();
        vm.prank(nio0);
        election.declareCandidate();

        vm.warp(block.timestamp + 6 days);
        vm.prank(nio1);
        election.voteForNominee(nio0);

        vm.prank(nio1);
        vm.expectRevert(abi.encodeWithSelector(NioElection.AlreadyVoted.selector, nio1));
        election.voteForNominee(nio0);
    }

    function testDisqualifyCandidate() public {
        election.startElection();
        vm.prank(nio0);
        election.declareCandidate();

        vm.warp(block.timestamp + 11 days);
        election.disqualifyCandidate(nio0);

        (,,, bool isEligible) = election.getCandidateInfo(nio0);
        assertEq(isEligible, false);
    }

    function testCannotDisqualifyCandidateBeforeComplianceProcess() public {
        election.startElection();
        vm.prank(nio0);
        election.declareCandidate();

        vm.warp(block.timestamp + 9 days);
        vm.expectRevert(
            abi.encodeWithSelector(
                NioElection.InvalidElectionPhase.selector,
                NioElection.ElectionPhase.NomineeSelection,
                NioElection.ElectionPhase.ComplianceProcess
            )
        );
        election.disqualifyCandidate(nio0);
    }

    function testCannotDisqualifyCandidateAfterComplianceProcess() public {
        election.startElection();
        vm.prank(nio0);
        election.declareCandidate();

        vm.warp(block.timestamp + 16 days);
        vm.expectRevert(
            abi.encodeWithSelector(
                NioElection.InvalidElectionPhase.selector,
                NioElection.ElectionPhase.MemberElection,
                NioElection.ElectionPhase.ComplianceProcess
            )
        );
        election.disqualifyCandidate(nio0);
    }

    function testCompleteElection() public {
        election.startElection();
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(nios[i]);
            election.declareCandidate();
        }

        // Nominee voting
        vm.warp(block.timestamp + 6 days);
        for (uint256 i = 5; i < nios.length; i++) {
            vm.prank(nios[i]);
            election.voteForNominee(nios[i % 5]);
        }

        // Member voting
        vm.warp(block.timestamp + 16 days);
        for (uint256 i = 5; i < nios.length; i++) {
            vm.prank(nios[i]);
            election.voteForMember(nios[i % 5]);
        }

        vm.warp(block.timestamp + 31 days);
        election.completeElection();

        assertFalse(election.isElectionActive());
        assertEq(election.electionCount(), 1);
    }

    function testCannotCompleteElectionBeforeEnd() public {
        election.startElection();
        vm.warp(block.timestamp + 29 days);
        vm.expectRevert(
            abi.encodeWithSelector(
                NioElection.InvalidElectionPhase.selector,
                NioElection.ElectionPhase.MemberElection,
                NioElection.ElectionPhase.Completed
            )
        );
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
        address[] memory currentNios = election.getElectedNios();
        assertEq(currentNios.length, 0);
    }
}
