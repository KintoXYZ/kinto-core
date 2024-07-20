// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import "@kinto-core/governance/EngenGovernance.sol";
import "@kinto-core/tokens/EngenCredits.sol";
import "@kinto-core/sample/Counter.sol";

import "@kinto-core-test/SharedSetup.t.sol";

contract EngenGovernanceTest is SharedSetup {
    address public _counter;

    function setUp() public override {
        super.setUp();
        registerApp(address(_kintoWallet), "engen credits", address(_engenCredits), new address[](0));
        registerApp(address(_kintoWallet), "engen governance", address(_engenGovernance), new address[](0));
        fundSponsorForApp(_owner, address(_engenCredits));
        fundSponsorForApp(_owner, address(_engenGovernance));
        _counter = address(new Counter());
        whitelistApp(address(_engenCredits));
        whitelistApp(address(_engenGovernance));
    }

    function testUp() public override {
        super.testUp();
        assertEq(_engenGovernance.votingDelay(), 1 days);
        assertEq(_engenGovernance.votingPeriod(), 3 weeks);
        assertEq(_engenGovernance.proposalThreshold(), 5e18);
        assertEq(_engenGovernance.quorum(block.number), 0); // no tokens minted
    }

    /* ============ Create Proposal tests ============ */

    function testCreateProposal() public {
        assertEq(_engenCredits.balanceOf(address(_kintoWallet)), 0);
        (UserOperation[] memory userOps, uint256 hashProposal) =
            mintCreditsAndcreateProposal(5e18, "First ENIP Proposal");
        _entryPoint.handleOps(userOps, payable(_owner));
        assertEq(_engenCredits.balanceOf(address(_kintoWallet)), 5e18);
        assert(_engenGovernance.state(hashProposal) == IGovernor.ProposalState.Pending);
        vm.warp(block.timestamp + 1 days + 1 seconds);
        assert(_engenGovernance.state(hashProposal) == IGovernor.ProposalState.Active);
    }

    function testCreateProposal_RevertWhen_WhenNotENoughCredits() public {
        (UserOperation[] memory userOps,) = mintCreditsAndcreateProposal(2e18, "First ENIP Proposal");
        vm.expectEmit(true, true, true, false);
        emit UserOperationRevertReason(
            _entryPoint.getUserOpHash(userOps[1]), userOps[1].sender, userOps[1].nonce, bytes("")
        );
        vm.recordLogs();
        _entryPoint.handleOps(userOps, payable(_owner));
        assertRevertReasonEq("Governor: proposer votes below proposal threshold");
    }

    /* ============ Vote Proposal tests ============ */

    function testVoteAndExecuteProposal() public {
        // set points for different address
        uint256[] memory points = new uint256[](1);
        points[0] = 20e18;
        address[] memory addresses = new address[](1);
        addresses[0] = address(123);
        vm.prank(_owner);
        _engenCredits.setCredits(addresses, points);
        // We Create the proposal
        (UserOperation[] memory userOps, uint256 hashProposal) =
            mintCreditsAndcreateProposal(10e18, "First ENIP Proposal");
        _entryPoint.handleOps(userOps, payable(_owner));
        vm.warp(block.timestamp + 1 days + 1 seconds);
        // Vote opens
        // A different user with credits can vote with enough votes to pass it
        vm.prank(address(123));
        _engenGovernance.castVote(hashProposal, 1); // vote for
        vm.warp(block.timestamp + 3 weeks + 1 seconds);
        assert(_engenGovernance.state(hashProposal) == IGovernor.ProposalState.Succeeded);
        // Execute

        address[] memory targets = new address[](1);
        targets[0] = address(_counter);
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeWithSignature("increment()");
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        _engenGovernance.execute(targets, values, data, keccak256(bytes("First ENIP Proposal")));
        // Check that it executed the proposal
        assertEq(Counter(_counter).count(), 1);
        assert(_engenGovernance.state(hashProposal) == IGovernor.ProposalState.Executed);
    }

    /* ============ Aux Function ============ */

    function mintCreditsAndcreateProposal(uint256 credits, string memory proposalDescription)
        internal
        returns (UserOperation[] memory, uint256)
    {
        {
            // set points
            uint256[] memory points = new uint256[](1);
            points[0] = credits;
            address[] memory addresses = new address[](1);
            addresses[0] = address(_kintoWallet);
            vm.prank(_owner);
            _engenCredits.setCredits(addresses, points);
        }

        // mint credit
        UserOperation[] memory userOps = new UserOperation[](2);
        userOps[0] = _createUserOperation(
            address(_kintoWallet),
            address(_engenCredits),
            _kintoWallet.getNonce(),
            privateKeys,
            abi.encodeWithSignature("mintCredits()"),
            address(_paymaster)
        );

        address[] memory targets = new address[](1);
        targets[0] = address(_counter);
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeWithSignature("increment()");
        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        userOps[1] = _createUserOperation(
            address(_kintoWallet),
            address(_engenGovernance),
            _kintoWallet.getNonce() + 1,
            privateKeys,
            abi.encodeWithSignature(
                "propose(address[],uint256[],bytes[],string)", targets, values, data, proposalDescription
            ),
            address(_paymaster)
        );

        return (userOps, _engenGovernance.hashProposal(targets, values, data, keccak256(bytes(proposalDescription))));
    }
}
