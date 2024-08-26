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
    uint256 internal constant EXECUTION_DELAY = 3 days;
    uint64 internal constant GOVERNOR_ROLE = 1;

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

        accessManager = new AccessManager(_owner);
        ownableCounter = new OwnableCounter();
        nio = new NioGuardians(_owner);
        governor = new NioGovernor(nio, address(accessManager));

        ownableCounter.transferOwnership(address(accessManager));

        for (uint256 index = 0; index < nios.length; index++) {
            vm.prank(_owner);
            nio.mint(nios[index], index);
        }

        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = OwnableCounter.increment.selector;
        vm.prank(_owner);
        accessManager.setTargetFunctionRole(address(ownableCounter), selectors, GOVERNOR_ROLE);

        vm.prank(_owner);
        accessManager.grantRole(GOVERNOR_ROLE, address(governor), uint32(EXECUTION_DELAY));

        skip(100);
    }

    function testUp() public override {
        super.testUp();

        assertEq(governor.votingDelay(), VOTING_DELAY);
        assertEq(governor.votingPeriod(), VOTING_PERIOD);
        assertEq(governor.baseDelaySeconds(), EXECUTION_DELAY);
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

        (uint32 delay, bool[] memory indirect, bool[] memory withDelay) = governor.proposalExecutionPlan(hashProposal);
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
        assertEq(uint8(governor.state(hashProposal)), uint8(IGovernor.ProposalState.Succeeded));

        queueProposal(hashProposal);
        vm.warp(block.timestamp + EXECUTION_DELAY + 1 seconds);

        // Execute
        (address[] memory targets, bytes[] memory data, uint256[] memory values, string memory desc) = getProposal();
        governor.execute(targets, values, data, keccak256(bytes(desc)));

        // Check that it executed the proposal
        assertEq(ownableCounter.count(), 1);
        assertEq(uint8(governor.state(hashProposal)), uint8(IGovernor.ProposalState.Executed));
    }

    /* ============ proposalNeedsQueuing ============ */

    function testProposalNeedsQueuing() public {
        uint256 proposalId = createProposal();

        // Check if the proposal needs queuing
        bool needsQueuing = governor.proposalNeedsQueuing(proposalId);

        // Since we're using GovernorTimelockAccess, the proposal should need queuing
        assertTrue(needsQueuing, "Proposal should need queuing");
    }

    /* ============ Cancel Proposal ============ */

    function testCancelProposal() public {
        uint256 proposalId = createProposal();

        // Cancel the proposal
        (address[] memory targets, bytes[] memory data, uint256[] memory values, string memory desc) = getProposal();
        vm.prank(address(nio0)); // The proposer should be able to cancel
        governor.cancel(targets, values, data, keccak256(bytes(desc)));

        // Check if the proposal is now in the Canceled state
        assertEq(
            uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Canceled), "Proposal should be canceled"
        );
    }

    /* ============ Helper ============ */

    function queueProposal(uint256 hashProposal) internal returns (uint256 hash) {
        governor.queue(hashProposal);
        assertEq(uint8(governor.state(hashProposal)), uint8(IGovernor.ProposalState.Queued));
    }

    function voteProposal(uint256 hashProposal) internal {
        vm.warp(block.timestamp + VOTING_DELAY + 1 seconds);

        // 5 out of 9 nios have to vote
        for (uint256 index = 0; index < 5; index++) {
            vm.prank(nios[index]);
            governor.castVote(hashProposal, 1);
        }
    }

    function getProposal()
        internal
        view
        returns (address[] memory targets, bytes[] memory data, uint256[] memory values, string memory desc)
    {
        targets = new address[](1);
        targets[0] = address(ownableCounter);
        data = new bytes[](1);
        data[0] = abi.encodeWithSelector(OwnableCounter.increment.selector);
        values = new uint256[](1);
        values[0] = 0;
        desc = "hello";
    }

    function createProposal() internal returns (uint256 hash) {
        (address[] memory targets, bytes[] memory data, uint256[] memory values, string memory desc) = getProposal();

        vm.prank(address(nio0));
        governor.propose(targets, values, data, desc);

        return governor.hashProposal(targets, values, data, keccak256(bytes(desc)));
    }
}
