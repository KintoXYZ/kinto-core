// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {IKintoWallet} from "../../src/interfaces/IKintoWallet.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";

// Executes governance proposals ENIP:1, ENIP:2 and ENIP:3
contract KintoMigration75DeployScript is MigrationHelper {
    function run() public override {
        super.run();
        address kintoWallet = _getChainDeployment("KintoWallet-admin");
        address governance = payable(_getChainDeployment("EngenGovernance"));
        whitelistGovernance(kintoWallet, governance);

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        bytes32 descriptionHash;

        // ENIP:1
        targets[0] = 0xdb791AF345A21588957E4e45596411b2Be2BD4cd;
        values[0] = 0;
        calldatas[0] = hex"d09de08a";
        descriptionHash = keccak256(abi.encodePacked("ENIP:1 - Kinto Constitution"));
        executeProposal(kintoWallet, governance, targets, values, calldatas, descriptionHash);

        // ENIP:2
        targets[0] = 0xdb791AF345A21588957E4e45596411b2Be2BD4cd;
        values[0] = 0;
        calldatas[0] = hex"d09de08a";
        descriptionHash = keccak256(abi.encodePacked("ENIP:2 - The Kinto Token"));
        executeProposal(kintoWallet, governance, targets, values, calldatas, descriptionHash);

        // ENIP:3
        targets[0] = 0xdb791AF345A21588957E4e45596411b2Be2BD4cd;
        values[0] = 0;
        calldatas[0] = hex"d09de08a";
        descriptionHash = keccak256(abi.encodePacked("ENIP:3 - The Mining Program"));
        executeProposal(kintoWallet, governance, targets, values, calldatas, descriptionHash);
    }

    function whitelistGovernance(address kintoWallet, address governance) public {
        uint256[] memory privKeys = new uint256[](1);
        privKeys[0] = deployerPrivateKey;

        address[] memory apps = new address[](1);
        apps[0] = governance;
        bool[] memory flags = new bool[](1);
        flags[0] = true;
        bytes memory selectorAndParams = abi.encodeWithSelector(IKintoWallet.whitelistApp.selector, apps, flags);
        _handleOps(selectorAndParams, kintoWallet, kintoWallet, 0, address(0), privKeys);
    }

    function executeProposal(
        address kintoWallet,
        address governance,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) public {
        uint256[] memory privKeys = new uint256[](2);
        privKeys[0] = deployerPrivateKey;
        privKeys[1] = LEDGER;

        bytes memory selectorAndParams =
            abi.encodeWithSelector(IGovernor.execute.selector, targets, values, calldatas, descriptionHash);
        _handleOps(selectorAndParams, kintoWallet, governance, 0, address(0), privKeys);
    }
}
