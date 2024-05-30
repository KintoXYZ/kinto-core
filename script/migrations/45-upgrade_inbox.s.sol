// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import "../../src/wallet/KintoWalletFactory.sol";
import "../../src/nitro-contracts/bridge/AbsInbox.sol";
import "../../src/nitro-contracts/bridge/Inbox.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import "forge-std/console2.sol";
import {L1GatewayRouter} from "@token-bridge-contracts/contracts/tokenbridge/ethereum/gateway/L1GatewayRouter.sol";

interface IUpgradeExecutor {
    function initialize(address admin, address[] memory executors) external;
    function execute(address upgrade, bytes memory upgradeCallData) external payable;
    function executeCall(address target, bytes memory targetCallData) external payable;
    function hasRole(bytes32 role, address account) external view returns (bool);
}

contract KintoMigration45DeployScript is MigrationHelper {
    function run() public override {
        super.run();

        TransparentUpgradeableProxy inbox =
            TransparentUpgradeableProxy(payable(0xBFfaA85c1756472fFC37e6D172A7eC0538C14474)); // L1
        ProxyAdmin proxyAdmin = ProxyAdmin(0x74C717C01425eb475A5fC55d2A4a9045fC9800df); // L1
        IUpgradeExecutor upgradeExecutor = IUpgradeExecutor(0x59B851c8b1643e0735Ec3F2f0e528f3d89c3408a); // L1

        // deploy new Inbox
        uint256 maxDataSize = AbsInbox(address(inbox)).maxDataSize();
        vm.broadcast();
        address impl = address(new Inbox(maxDataSize));
        console2.log("InboxV2-impl: ", impl);

        // upgrade Inbox (only from multisig)
        if (!upgradeExecutor.hasRole(keccak256("EXECUTOR_ROLE"), msg.sender)) {
            console2.log("Sender does not have EXECUTOR_ROLE");
            return;
        }

        bytes memory upgradeCallData = abi.encodeWithSelector(ProxyAdmin.upgrade.selector, inbox, impl);
        vm.broadcast();
        upgradeExecutor.executeCall(address(proxyAdmin), upgradeCallData);

        // function below no longer exists
        // vm.broadcast();
        // AbsInbox(address(inbox)).initializeL2AllowList();
    }
}
