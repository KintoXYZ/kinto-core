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

    function setUp() public override {
        super.setUp();

        kToken = BridgedKinto(payable(address(new UUPSProxy(address(new BridgedKinto()), ""))));
        kToken.initialize("KINTO TOKEN", "KINTO", admin, admin, admin);

        nioNFT = new NioGuardians(admin);
        election = new NioElection(kToken, nioNFT, _kintoID);

        // Distribute tokens
        uint256 kAmount = 100e18;
        for (uint256 i = 0; i < users.length; i++) {
            vm.prank(admin);
            kToken.mint(users[i], kAmount);
            vm.prank(users[i]);
            kToken.delegate(users[i]);
        }
    }

    function testUp() public override {}

    function testStartElection() public {}

    function testCannotStartActiveElection() public {
        election.startElection();
        vm.expectRevert(abi.encodeWithSelector(NioElection.ElectionAlreadyActive.selector, block.timestamp));
        election.startElection();
    }

    function testCannotStartElectionTooEarly() public {
        election.startElection();
        vm.warp(block.timestamp + 31 days);
        election.electNios();

        vm.warp(block.timestamp + 179 days); // Just before the ELECTION_INTERVAL
        uint256 nextElectionTime = election.getNextElectionTime();
        vm.expectRevert(
            abi.encodeWithSelector(NioElection.TooEarlyForNewElection.selector, block.timestamp, nextElectionTime)
        );
        election.startElection();
    }

    function testSubmitCandidate() public {}

    function testCannotSubmitCandidateAfterDeadline() public {
        election.startElection();
        vm.warp(block.timestamp + 6 days);
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                NioElection.InvalidElectionPhase.selector,
                NioElection.ElectionPhase.CandidateVoting,
                NioElection.ElectionPhase.CandidateSubmission
            )
        );
        election.submitCandidate();
    }

    function testVoteForCandidate() public {}

    function testVoteForNominee() public {}

    function testCannotVoteForCandidateBeforeCandidateVoting() public {
        election.startElection();
        vm.prank(alice);
        election.submitCandidate();

        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(
                NioElection.InvalidElectionPhase.selector,
                NioElection.ElectionPhase.CandidateSubmission,
                NioElection.ElectionPhase.CandidateVoting
            )
        );
        election.voteForCandidate(alice);
    }

    function testCannotVoteForNomineeBeforeNomineeVoting() public {
        election.startElection();
        vm.prank(alice);
        election.submitCandidate();

        vm.warp(block.timestamp + 6 days);
        vm.prank(bob);
        election.voteForCandidate(alice);

        vm.prank(charlie);
        vm.expectRevert(
            abi.encodeWithSelector(
                NioElection.InvalidElectionPhase.selector,
                NioElection.ElectionPhase.CandidateVoting,
                NioElection.ElectionPhase.NomineeVoting
            )
        );
        election.voteForNominee(alice);
    }

    function testCannotVoteTwice() public {
        election.startElection();
        vm.prank(alice);
        election.submitCandidate();

        vm.warp(block.timestamp + 6 days);
        vm.prank(bob);
        election.voteForCandidate(alice);

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(NioElection.AlreadyVoted.selector, bob));
        election.voteForCandidate(alice);
    }

    function testElectNios() public {}

    function testCannotElectNiosBeforeEnd() public {
        election.startElection();
        vm.warp(block.timestamp + 29 days);
        vm.expectRevert(
            abi.encodeWithSelector(
                NioElection.InvalidElectionPhase.selector,
                NioElection.ElectionPhase.NomineeVoting,
                NioElection.ElectionPhase.Completed
            )
        );
        election.electNios();
    }

    function testAlternatingNiosToElect() public {}

    function testGetElectedNios() public {}
}
