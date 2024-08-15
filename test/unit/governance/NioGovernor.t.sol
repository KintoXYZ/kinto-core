// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {IGovernor} from "@openzeppelin-5.0.1/contracts/governance/IGovernor.sol";
import {AccessManager} from "@openzeppelin-5.0.1/contracts/access/manager/AccessManager.sol";


import {OwnableCounter} from "@kinto-core/sample/OwnableCounter.sol";
import {NioGovernor} from "@kinto-core/governance/NioGovernor.sol";
import {NioGuardians} from "@kinto-core/tokens/NioGuardians.sol";

import {SharedSetup} from "@kinto-core-test/SharedSetup.t.sol";

import 'forge-std/console2.sol';

contract NioGovernorTest is SharedSetup {
    NioGovernor internal governor;
    NioGuardians internal nio;
    OwnableCounter internal ownableCounter;
    AccessManager internal accessManager;

    function setUp() public override {
        super.setUp();

        accessManager = new AccessManager(_owner);
        ownableCounter = new OwnableCounter();
        nio = new NioGuardians(_owner);
        governor = new NioGovernor(nio, address(accessManager));

        vm.prank(_owner);
        nio.mint(address(_kintoWallet), 0);

        console2.log('governor.clock():', governor.clock());
        console2.log('governor.CLOCK_MODE():', governor.CLOCK_MODE());

        skip(100);
    }

    function testUp() public override {
        super.testUp();

        assertEq(governor.votingDelay(), 3 days);
        assertEq(governor.votingPeriod(), 5 days);
        assertEq(governor.proposalThreshold(), 1);
        assertEq(governor.quorum(block.number), 5);

        assertEq(nio.getVotes(address(_kintoWallet)), 1);
        assertEq(nio.getPastVotes(address(_kintoWallet), block.timestamp - 1), 1);
    }

    /* ============ Create Proposal ============ */

    function testCreateProposal() public {

        address[] memory targets = new address[](1);
        targets[0] = address(ownableCounter);
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeWithSignature("increment()");
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        string memory proposalDescription = 'hello';

        vm.prank(address(_kintoWallet));
        governor.propose(targets, values, data, proposalDescription);

        uint256 hashProposal = governor.hashProposal(targets, values, data, keccak256(bytes(proposalDescription)));

        assertEq(uint8(governor.state(hashProposal)), uint8(IGovernor.ProposalState.Pending));

        vm.warp(block.timestamp + 3 days + 1 seconds);
        assertEq(uint8(governor.state(hashProposal) ), uint8(IGovernor.ProposalState.Active));
    }

    /* ============ Vote Proposal ============ */

    /* ============ Helper ============ */

}

