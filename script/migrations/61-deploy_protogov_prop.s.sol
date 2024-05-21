// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../../src/tokens/EngenCredits.sol";
import "../../src/governance/EngenGovernance.sol";
import "@openzeppelin/contracts/governance/Governor.sol";

import "@kinto-core-script/utils/MigrationHelper.sol";

contract KintoMigration61DeployScript is MigrationHelper {
    using ECDSAUpgradeable for bytes32;

    function run() public override {
        super.run();
        console.log("Executing with address", msg.sender, vm.envAddress("LEDGER_ADMIN"));

        EngenCredits credits = EngenCredits(_getChainDeployment("EngenCredits"));
        EngenGovernance governance = EngenGovernance(payable(_getChainDeployment("EngenGovernance")));

        bytes memory selectorAndParams;
        address[] memory wallets = new address[](1);
        wallets[0] = _getChainDeployment("KintoWallet-admin");
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 5e23;
        selectorAndParams = abi.encodeWithSelector(EngenCredits.setCredits.selector, wallets, amounts);
        _handleOps(selectorAndParams, address(credits), deployerPrivateKey);

        _whitelistApp(_getChainDeployment("EngenGovernance"), deployerPrivateKey, true);

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
        description = "ENIP:1 - Kinto Constitution";

        selectorAndParams = abi.encodeWithSelector(Governor.propose.selector, targets, values, data, description);
        _handleOps(selectorAndParams, address(governance), deployerPrivateKey);

        proposalId = governance.hashProposal(targets, values, data, keccak256(bytes(description)));
        require(governance.state(proposalId) == IGovernor.ProposalState.Pending);
        console.log("Proposal ID 1:", proposalId);

        description = "ENIP:2 - The Kinto Token";
        selectorAndParams = abi.encodeWithSelector(Governor.propose.selector, targets, values, data, description);
        _handleOps(selectorAndParams, address(governance), deployerPrivateKey);
        proposalId = governance.hashProposal(targets, values, data, keccak256(bytes(description)));
        require(governance.state(proposalId) == IGovernor.ProposalState.Pending);
        console.log("Proposal ID 2:", proposalId);

        description = "ENIP:3 - The Mining Program";
        selectorAndParams = abi.encodeWithSelector(Governor.propose.selector, targets, values, data, description);
        _handleOps(selectorAndParams, address(governance), deployerPrivateKey);

        proposalId = governance.hashProposal(targets, values, data, keccak256(bytes(description)));
        require(governance.state(proposalId) == IGovernor.ProposalState.Pending);
        console.log("Proposal ID 3:", proposalId);
    }
}
