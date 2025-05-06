// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../../src/governance/ProtoGovernance.sol";
import "@openzeppelin/contracts/governance/Governor.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";

import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import "forge-std/console2.sol";

contract KintoMigration61DeployScript is MigrationHelper {
    function run() public override {
        super.run();

        ProtoGovernance governance = ProtoGovernance(payable(_getChainDeployment("ProtoGovernance")));

        bytes memory selectorAndParams;

        // _whitelistApp(_getChainDeployment("ProtoGovernance"), true);
        // _whitelistApp(_getChainDeployment("KINTO"), true);
        // Delegate
        // selectorAndParams = abi.encodeWithSelector(ERC20Votes.delegate.selector, 0x2e2B1c42E38f5af81771e65D87729E57ABD1337a);
        // _handleOps(selectorAndParams, address(_getChainDeployment("KINTO")));
        // console2.log("Delegated to", 0x2e2B1c42E38f5af81771e65D87729E57ABD1337a);

        address[] memory targets;
        bytes[] memory data;
        uint256[] memory values;
        string memory description;
        uint256 proposalId;

        targets = new address[](1);
        targets[0] = address(_getChainDeployment("Counter"));
        data = new bytes[](1);
        data[0] = abi.encodeWithSignature("increment()");
        values = new uint256[](1);
        values[0] = 0;
        description = "KIP:1 - Nio Elections";

        selectorAndParams = abi.encodeWithSelector(Governor.propose.selector, targets, values, data, description);
        _handleOps(selectorAndParams, address(governance));

        proposalId = governance.hashProposal(targets, values, data, keccak256(bytes(description)));
        require(governance.state(proposalId) == IGovernor.ProposalState.Pending);
        console2.log("Proposal ID 1:", proposalId);

        description = "KIP:2 - Buybacks";
        selectorAndParams = abi.encodeWithSelector(Governor.propose.selector, targets, values, data, description);
        _handleOps(selectorAndParams, address(governance));
        proposalId = governance.hashProposal(targets, values, data, keccak256(bytes(description)));
        require(governance.state(proposalId) == IGovernor.ProposalState.Pending);
        console2.log("Proposal ID 2:", proposalId);

        description = "KIP:3 - Clawback from MM";
        selectorAndParams = abi.encodeWithSelector(Governor.propose.selector, targets, values, data, description);
        _handleOps(selectorAndParams, address(governance));

        proposalId = governance.hashProposal(targets, values, data, keccak256(bytes(description)));
        require(governance.state(proposalId) == IGovernor.ProposalState.Pending);
        console2.log("Proposal ID 3:", proposalId);
    }
}
