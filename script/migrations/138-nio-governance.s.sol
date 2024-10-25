// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {NioElection} from "@kinto-core/governance/NioElection.sol";
import {NioGuardians} from "@kinto-core/tokens/NioGuardians.sol";
import {BridgedKinto} from "@kinto-core/tokens/bridged/BridgedKinto.sol";
import {UUPSProxy} from "@kinto-core-test/helpers/UUPSProxy.sol";
import {AccessManager} from "@openzeppelin-5.0.1/contracts/access/manager/AccessManager.sol";
import {NioGovernor} from "@kinto-core/governance/NioGovernor.sol";
import {IKintoID} from "@kinto-core/interfaces/IKintoID.sol";

import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";

contract DeployScript is MigrationHelper {
    function run() public override {
        super.run();

        (bytes32 salt, address expectedAddress) = mineSalt(
            keccak256(abi.encodePacked(type(NioGuardians).creationCode, abi.encode(kintoAdminWallet))), "010000"
        );

        vm.broadcast(deployerPrivateKey);
        NioGuardians nioNFT = new NioGuardians{salt: salt}(address(kintoAdminWallet));

        assertEq(address(nioNFT), address(expectedAddress));
        assertEq(nioNFT.owner(), address(kintoAdminWallet));

        saveContractAddress("NioGuardians", address(nioNFT));

        vm.broadcast(deployerPrivateKey);
        NioElection election = new NioElection{salt: 0}(
            BridgedKinto(_getChainDeployment("KINTO")), nioNFT, IKintoID(_getChainDeployment("KintoID"))
        );

        assertEq(address(election.kToken()), _getChainDeployment("KINTO"));
        assertEq(address(election.nioNFT()), address(nioNFT));
        assertEq(address(election.kintoID()), _getChainDeployment("KintoID"));

        saveContractAddress("NioElectionV1-impl", address(election));

        (salt, expectedAddress) =
            mineSalt(keccak256(abi.encodePacked(type(UUPSProxy).creationCode, abi.encode(election, ""))), "010E1E");

        vm.broadcast(deployerPrivateKey);
        address proxy = address(new UUPSProxy{salt: salt}(address(election), ""));

        assertEq(proxy, address(expectedAddress));

        _whitelistApp(proxy);

        _handleOps(abi.encodeWithSelector(NioElection.initialize.selector, kintoAdminWallet), proxy);

        assertEq(NioElection(proxy).owner(), kintoAdminWallet);

        saveContractAddress("NioElection", proxy);

        (salt, expectedAddress) = mineSalt(
            keccak256(abi.encodePacked(type(AccessManager).creationCode, abi.encode(kintoAdminWallet))), "ACC000"
        );

        vm.broadcast(deployerPrivateKey);
        AccessManager accessManager = new AccessManager{salt: salt}(kintoAdminWallet);

        assertEq(address(accessManager), address(expectedAddress));
        (bool isMember,) = accessManager.hasRole(0, kintoAdminWallet);
        assertTrue(isMember);

        saveContractAddress("AccessManager", address(accessManager));

        (salt, expectedAddress) = mineSalt(
            keccak256(abi.encodePacked(type(NioGovernor).creationCode, abi.encode(nioNFT, accessManager))), "010600"
        );
        vm.broadcast(deployerPrivateKey);
        NioGovernor governor = new NioGovernor{salt: salt}(nioNFT, address(accessManager));
        assertEq(address(governor), address(expectedAddress));

        assertEq(governor.quorum(block.number), 5);
        assertEq(governor.proposalThreshold(), 1);

        saveContractAddress("NioGovernor", address(governor));
    }
}
