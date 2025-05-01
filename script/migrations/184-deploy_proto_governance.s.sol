// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@kinto-core/governance/ProtoGovernance.sol";
import {BridgedKinto} from "@kinto-core/tokens/bridged/BridgedKinto.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import {KintoAppRegistry} from "@kinto-core/apps/KintoAppRegistry.sol";
import "forge-std/console2.sol";

contract KintoMigration55DeployScript is MigrationHelper {
    function run() public override {
        super.run();

        address token = _getChainDeployment("KINTO");
        console2.log("token: %s", token);

        bytes32 initCodeHash = keccak256(abi.encodePacked(type(ProtoGovernance).creationCode, abi.encode(token)));

        (bytes32 salt, address expectedAddress) = mineSalt(initCodeHash, "6033B0");
        vm.broadcast(deployerPrivateKey);
        address governance = create2(abi.encodePacked(type(ProtoGovernance).creationCode, abi.encode(token)), salt);

        require(expectedAddress == governance, "Address mining failed");

        require(ProtoGovernance(payable(governance)).votingDelay() == 1 days, "governance failed to deploy");
        require(
            keccak256(bytes(BridgedKinto(token).CLOCK_MODE())) == keccak256(bytes("mode=timestamp")),
            "token has not voting"
        );

        KintoAppRegistry registry = KintoAppRegistry(_getChainDeployment("KintoAppRegistry"));
        _handleOps(
            abi.encodeWithSelector(
                KintoAppRegistry.registerApp.selector,
                "ProtoGovernance",
                address(governance),
                new address[](0),
                [uint256(0), uint256(0), uint256(0), uint256(0)],
                new address[](0)
            ),
            address(registry)
        );

        saveContractAddress("ProtoGovernance", governance);
    }
}
