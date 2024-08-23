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
        uint256 kAmount = 100e18;
        for (uint256 i = 0; i < users.length; i++) {
            vm.prank(admin);
            kToken.mint(users[i], kAmount);
            vm.prank(users[i]);
            kToken.delegate(users[i]);
        }
    }

    function testUp() public virtual {}

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

    function testMultipleUsersDeclareCandidate() public {
        election.startElection();

        for (uint256 i = 0; i < 5; i++) {
            vm.prank(users[i]);
            election.submitNominee();
            (address addr,,,) = election.getCandidateInfo(users[i]);
            assertEq(addr, users[i]);
        }
    }

    function testCannotDeclareCandidateAfterDeadline() public {
        election.startElection();
        vm.warp(block.timestamp + 6 days);
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                NioElection.InvalidElectionPhase.selector,
                NioElection.ElectionPhase.NomineeSelection,
                NioElection.ElectionPhase.ContenderSubmission
            )
        );
        election.submitNominee();
    }

    function testMultipleUsersVoteForNominee() public {
        election.startElection();
        for (uint256 i = 0; i < 3; i++) {
            vm.prank(users[i]);
            election.submitNominee();
        }

        vm.warp(block.timestamp + 6 days);
        for (uint256 i = 3; i < users.length; i++) {
            vm.prank(users[i]);
            election.voteForNominee(users[i % 3]);
        }

        for (uint256 i = 0; i < 3; i++) {
            (, uint256 nomineeVotes,,) = election.getCandidateInfo(users[i]);
            assertGt(nomineeVotes, 0);
        }
    }

    function testMultipleUsersVoteForMember() public {
        election.startElection();
        for (uint256 i = 0; i < 3; i++) {
            vm.prank(users[i]);
            election.submitNominee();
        }

        // Make candidates eligible
        vm.warp(block.timestamp + 6 days);
        for (uint256 i = 3; i < 6; i++) {
            vm.prank(users[i]);
            election.voteForNominee(users[i % 3]);
        }

        // Vote for members
        vm.warp(block.timestamp + 11 days);
        for (uint256 i = 6; i < users.length; i++) {
            vm.prank(users[i]);
            election.voteForMember(users[i % 3]);
        }

        for (uint256 i = 0; i < 3; i++) {
            (,, uint256 electionVotes,) = election.getCandidateInfo(users[i]);
            assertGt(electionVotes, 0);
        }
    }

    function testCannotVoteForNomineeBeforeNomineeSelection() public {
        election.startElection();
        vm.prank(alice);
        election.submitNominee();

        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(
                NioElection.InvalidElectionPhase.selector,
                NioElection.ElectionPhase.ContenderSubmission,
                NioElection.ElectionPhase.NomineeSelection
            )
        );
        election.voteForNominee(alice);
    }

    function testCannotVoteForMemberBeforeMemberElection() public {
        election.startElection();
        vm.prank(alice);
        election.submitNominee();

        vm.warp(block.timestamp + 6 days);
        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(
                NioElection.InvalidElectionPhase.selector,
                NioElection.ElectionPhase.NomineeSelection,
                NioElection.ElectionPhase.MemberElection
            )
        );
        election.voteForMember(alice);
    }

    function testCannotVoteTwice() public {
        election.startElection();
        vm.prank(alice);
        election.submitNominee();

        vm.warp(block.timestamp + 6 days);
        vm.prank(bob);
        election.voteForNominee(alice);

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(NioElection.AlreadyVoted.selector, bob));
        election.voteForNominee(alice);
    }

    function testDisqualifyMultipleCandidates() public {
        election.startElection();
        for (uint256 i = 0; i < 3; i++) {
            vm.prank(users[i]);
            election.submitNominee();
        }

        bool isEligible;

        vm.warp(block.timestamp + 11 days);
        for (uint256 i = 0; i < 2; i++) {
            election.disqualifyCandidate(users[i]);
            (,,, isEligible) = election.getCandidateInfo(users[i]);
            assertEq(isEligible, false);
        }
        (,,, isEligible) = election.getCandidateInfo(users[2]);
        assertEq(isEligible, true);
    }

    function testCannotDisqualifyCandidateBeforeComplianceProcess() public {
        election.startElection();
        vm.prank(alice);
        election.submitNominee();

        vm.warp(block.timestamp + 9 days);
        vm.expectRevert(
            abi.encodeWithSelector(
                NioElection.InvalidElectionPhase.selector,
                NioElection.ElectionPhase.NomineeSelection,
                NioElection.ElectionPhase.ComplianceProcess
            )
        );
        election.disqualifyCandidate(alice);
    }

    function testCannotDisqualifyCandidateAfterComplianceProcess() public {
        election.startElection();
        vm.prank(alice);
        election.submitNominee();

        vm.warp(block.timestamp + 16 days);
        vm.expectRevert(
            abi.encodeWithSelector(
                NioElection.InvalidElectionPhase.selector,
                NioElection.ElectionPhase.MemberElection,
                NioElection.ElectionPhase.ComplianceProcess
            )
        );
        election.disqualifyCandidate(alice);
    }

    function testCompleteElectionWithMultipleUsers() public {
        election.startElection();
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(users[i]);
            election.submitNominee();
        }

        // Nominee voting
        vm.warp(block.timestamp + 6 days);
        for (uint256 i = 5; i < users.length; i++) {
            vm.prank(users[i]);
            election.voteForNominee(users[i % 5]);
        }

        // Member voting
        vm.warp(block.timestamp + 16 days);
        for (uint256 i = 5; i < users.length; i++) {
            vm.prank(users[i]);
            election.voteForMember(users[i % 5]);
        }

        vm.warp(block.timestamp + 31 days);
        election.completeElection();

        assertFalse(election.isElectionActive());
        assertEq(election.electionCount(), 1);

        address[] memory electedNios = election.getElectedNios();
        assertEq(electedNios.length, 4); // First election elects 4 Nios
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
