// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import "../../src/wallet/KintoWalletFactory.sol";
import "../../src/nitro-contracts/bridge/AbsInbox.sol";
import "../../src/nitro-contracts/bridge/Inbox.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import {L1GatewayRouter} from "@token-bridge-contracts/contracts/tokenbridge/ethereum/gateway/L1GatewayRouter.sol";
import "forge-std/console2.sol";

interface IUpgradeExecutor {
    function initialize(address admin, address[] memory executors) external;
    function execute(address upgrade, bytes memory upgradeCallData) external payable;
    function executeCall(address target, bytes memory targetCallData) external payable;
    function hasRole(bytes32 role, address account) external view returns (bool);
}

contract Script is MigrationHelper {
    function run() public override {
        super.run();

        TransparentUpgradeableProxy inbox =
            TransparentUpgradeableProxy(payable(0xD560b3Cd927355FB9f45cbFbAdbC8A522138D823));
        ProxyAdmin proxyAdmin = ProxyAdmin(0x017a5fB3E2CFF1a0300FEfE7aC77c8250fEE73da);
        IUpgradeExecutor upgradeExecutor = IUpgradeExecutor(0xa2dc657a9FE7326E8Be2a57D2372ffBD81d120e6);

        if (!upgradeExecutor.hasRole(keccak256("EXECUTOR_ROLE"), vm.addr(deployerPrivateKey))) {
            revert("Sender does not have EXECUTOR_ROLE");
        }

        // upgrade Inbox
        uint256 maxDataSize = AbsInbox(address(inbox)).maxDataSize();
        vm.broadcast(deployerPrivateKey);
        address impl = address(new Inbox(maxDataSize));
        console2.log("InboxV2-impl: ", impl);
        bytes memory upgradeCallData = abi.encodeWithSelector(ProxyAdmin.upgrade.selector, inbox, impl);

        vm.broadcast(deployerPrivateKey);
        upgradeExecutor.executeCall(address(proxyAdmin), upgradeCallData);
    }
}
