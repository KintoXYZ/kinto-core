// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import "../../src/nitro-contracts/bridge/AbsInbox.sol";
import "../../src/nitro-contracts/bridge/Inbox.sol";
import "@kinto-core/util/ETHSweeper.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import {L1GatewayRouter} from "@token-bridge-contracts/contracts/tokenbridge/ethereum/gateway/L1GatewayRouter.sol";

import "forge-std/console2.sol";

interface IUpgradeExecutor {
    function executeCall(address target, bytes memory targetCallData) external payable;
    function hasRole(bytes32 role, address account) external view returns (bool);
}

contract KintoMigration45DeployScript is MigrationHelper {
    address public constant COUNCIL = 0x17Eb10e12a78f986C78F973Fc70eD88072B33B7d;
    address public constant SAFE = 0x2E7111Ef34D39b36EC84C656b947CA746e495Ff6;
    address public constant SWEEPER = 0x90c824B62a94Fc2B78E6Ba010aE583Cde3cAEcFb;

    function run() public override {
        super.run();

        TransparentUpgradeableProxy bridge =
            TransparentUpgradeableProxy(payable(0x859a53Fe2C8DA961387030E7CB498D6D20d0B2DB)); // L1
        ProxyAdmin proxyAdmin = ProxyAdmin(0x74C717C01425eb475A5fC55d2A4a9045fC9800df); // L1
        IUpgradeExecutor upgradeExecutor = IUpgradeExecutor(0x59B851c8b1643e0735Ec3F2f0e528f3d89c3408a); // L1

        bytes memory upgradeCallData = abi.encodeWithSelector(ProxyAdmin.upgrade.selector, bridge, SWEEPER);
        console2.log('calldata:');
        console2.logBytes(upgradeCallData);
        vm.prank(COUNCIL);
        upgradeExecutor.executeCall(address(proxyAdmin), upgradeCallData);

        console2.log("balance before:", SAFE.balance);

        // Sweep the funds
        ETHSweeper(address(bridge)).sweep();

        console2.log("balance after:", SAFE.balance);
    }
}
