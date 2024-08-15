// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {IGovernor} from "@openzeppelin-5.0.1/contracts/governance/IGovernor.sol";
import {AccessManager} from "@openzeppelin-5.0.1/contracts/access/manager/AccessManager.sol";

import {OwnableCounter} from "@kinto-core/sample/OwnableCounter.sol";
import {NioGovernor} from "@kinto-core/governance/NioGovernor.sol";
import {NioGuardians} from "@kinto-core/tokens/NioGuardians.sol";

import {SharedSetup} from "@kinto-core-test/SharedSetup.t.sol";

import "forge-std/console2.sol";

contract NioGovernorTest is SharedSetup {
    NioGovernor internal governor;
    NioGuardians internal nio;
    OwnableCounter internal ownableCounter;
    AccessManager internal accessManager;
    uint256 internal constant VOTING_DELAY = 3 days; 
    uint256 internal constant VOTING_PERIOD = 5 days; 

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

        nios.push(nio0);
        nios.push(nio1);
        nios.push(nio2);
        nios.push(nio3);
        nios.push(nio4);
        nios.push(nio5);
        nios.push(nio6);
        nios.push(nio7);
        nios.push(nio8);

        accessManager = new AccessManager(_owner);
        ownableCounter = new OwnableCounter();
        nio = new NioGuardians(_owner);
        governor = new NioGovernor(nio, address(accessManager));

        ownableCounter.transferOwnership(address(governor));

        for (uint256 index = 0; index < nios.length; index++) {
            vm.prank(_owner);
            nio.mint(nios[index], index);
        }

        skip(100);
    }

    function testUp() public override {
        super.testUp();

        assertEq(governor.votingDelay(), VOTING_DELAY);
        assertEq(governor.votingPeriod(), VOTING_PERIOD);
        assertEq(governor.proposalThreshold(), 1);
        assertEq(governor.quorum(block.number), 5);

        assertEq(nio.getVotes(nio0), 1);
        assertEq(nio.getPastVotes(nio0, block.timestamp - 1), 1);
    }

    /* ============ Create Proposal ============ */

    function testCreateProposal() public {
        uint256 hashProposal = createProposal();

        assertEq(uint8(governor.state(hashProposal)), uint8(IGovernor.ProposalState.Pending));

        vm.warp(block.timestamp + VOTING_DELAY + 1 seconds);
        assertEq(uint8(governor.state(hashProposal)), uint8(IGovernor.ProposalState.Active));
    }

    /* ============ Vote Proposal ============ */

    function testVoteProposal() public {
        uint256 hashProposal = createProposal();

        voteProposal(hashProposal);

        vm.warp(block.timestamp + VOTING_PERIOD + 1 seconds);
        assertEq(uint8(governor.state(hashProposal)), uint8(IGovernor.ProposalState.Succeeded));
    }

    /* ============ Execute Proposal ============ */

    function testExecuteProposal() public {
        uint256 hashProposal = createProposal();

        voteProposal(hashProposal);

        vm.warp(block.timestamp + VOTING_PERIOD + 1 seconds);

        // Execute
        (address[] memory targets, bytes[] memory data, uint256[] memory values, string memory desc) = getProposal();
        governor.execute(targets, values, data, keccak256(bytes(desc)));

        // Check that it executed the proposal
        assertEq(ownableCounter.count(), 1);
        assertEq(uint8(governor.state(hashProposal)), uint8(IGovernor.ProposalState.Executed));
    }

    /* ============ Helper ============ */

    function voteProposal(uint256 hashProposal) internal returns (uint256 hash) {
        vm.warp(block.timestamp + 3 days + 1 seconds);

        // 5 out of 9 nios have to vote
        for (uint256 index = 0; index < 5; index++) {
            vm.prank(nios[index + 1]);
            governor.castVote(hashProposal, 1);
        }
    }

    function getProposal() internal returns (address[] memory targets, bytes[] memory data, uint256[] memory values, string memory desc) {
        targets = new address[](1);
        targets[0] = address(ownableCounter);
        data = new bytes[](1);
        data[0] = abi.encodeWithSignature("increment()");
        values = new uint256[](1);
        values[0] = 0;
        desc= "hello";
    }

    function createProposal() internal returns (uint256 hash) {
        (address[] memory targets, bytes[] memory data, uint256[] memory values, string memory desc) = getProposal();

        vm.prank(address(nio0));
        governor.propose(targets, values, data, desc);

        return governor.hashProposal(targets, values, data, keccak256(bytes(desc)));
    }
}
