// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@kinto-core/tokens/EngenCredits.sol";
import "@kinto-core/governance/EngenGovernance.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import {KintoAppRegistry} from "@kinto-core/apps/KintoAppRegistry.sol";
import "forge-std/console2.sol";

contract KintoMigration55DeployScript is MigrationHelper {
    function run() public override {
        super.run();

        bytes memory bytecode;
        address implementation;
        address proxy;

        // Upgrades engen credits
        proxy = _getChainDeployment("EngenCredits");
        bytecode = abi.encodePacked(type(EngenCredits).creationCode);
        console2.log("proxy: %s", proxy);
        implementation = _deployImplementation("EngenCredits", "V3", bytecode);
        _upgradeTo(proxy, implementation, deployerPrivateKey);

        // Deploy EngenGovernance
        bytecode = abi.encodePacked(type(EngenGovernance).creationCode, abi.encode(_getChainDeployment("EngenCredits")));
        address governance = _deployImplementation("EngenGovernance", "V1", bytecode);

        _fundPaymaster(governance, deployerPrivateKey);
        _whitelistApp(governance);

        require(EngenGovernance(payable(governance)).votingDelay() == 1 days, "governance failed to deploy");
        require(
            keccak256(bytes(EngenCredits(proxy).CLOCK_MODE())) == keccak256(bytes("mode=timestamp")),
            "credits did not upgrade"
        );
        vm.broadcast(deployerPrivateKey);
        KintoAppRegistry registry = KintoAppRegistry(_getChainDeployment("KintoAppRegistry"));
        registry.registerApp(
            "EngenGovernance",
            address(governance),
            new address[](0),
            [uint256(0), uint256(0), uint256(0), uint256(0)],
            new address[](0)
        );
    }
}
