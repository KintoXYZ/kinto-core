// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import "../../src/wallet/KintoWalletFactory.sol";
import "../../src/bridger/token-bridge-contracts//L2CustomGateway.sol";
import "../../src/bridger/token-bridge-contracts//L2ERC20Gateway.sol";
import "../../src/bridger/token-bridge-contracts//L2WethGateway.sol";

import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import "forge-std/console2.sol";

interface IUpgradeExecutor {
    function initialize(address admin, address[] memory executors) external;
    function execute(address upgrade, bytes memory upgradeCallData) external payable;
    function executeCall(address target, bytes memory targetCallData) external payable;
    function hasRole(bytes32 role, address account) external view returns (bool);
}

contract KintoMigration41DeployScript is MigrationHelper {
    function run() public override {
        super.run();

        TransparentUpgradeableProxy l2CustomGateway =
            TransparentUpgradeableProxy(payable(0x094F8C3eA1b5671dd19E15eCD93C80d2A33fCA99)); // devnet
        TransparentUpgradeableProxy l2ERC20Gateway =
            TransparentUpgradeableProxy(payable(0x6A8d32c495df943212B7788114e41103047150a5)); // devnet
        TransparentUpgradeableProxy l2WethGateway =
            TransparentUpgradeableProxy(payable(0x79B47F0695608aD8dc90E400a3E123b02eB72D24)); // devnet
        ProxyAdmin proxyAdmin = ProxyAdmin(0x6fF2194e07E970caFd33A0eae5FEF5c50406bcf8); // devnet
        IUpgradeExecutor upgradeExecutor = IUpgradeExecutor(0x6B0d3F40DeD9720938DB274f752F1e11532c2640); // devnet

        if (!upgradeExecutor.hasRole(keccak256("EXECUTOR_ROLE"), vm.addr(deployerPrivateKey))) {
            revert("Sender does not have EXECUTOR_ROLE");
        }

        // L2CustomGateway
        bytes memory bytecode = abi.encodePacked(type(L2CustomGateway).creationCode);
        address impl = _deployImplementation("L2CustomGateway", "V2", bytecode);
        bytes memory upgradeCallData = abi.encodeWithSelector(ProxyAdmin.upgrade.selector, l2CustomGateway, impl);

        vm.broadcast(deployerPrivateKey);
        upgradeExecutor.executeCall(address(proxyAdmin), upgradeCallData);

        // L2ERC20Gateway
        bytecode = abi.encodePacked(type(L2ERC20Gateway).creationCode);
        impl = _deployImplementation("L2ERC20Gateway", "V2", bytecode);
        upgradeCallData = abi.encodeWithSelector(ProxyAdmin.upgrade.selector, l2ERC20Gateway, impl);

        vm.broadcast(deployerPrivateKey);
        upgradeExecutor.executeCall(address(proxyAdmin), upgradeCallData);

        // L2WethGateway
        bytecode = abi.encodePacked(type(L2WethGateway).creationCode);
        impl = _deployImplementation("L2WethGateway", "V2", bytecode);
        upgradeCallData = abi.encodeWithSelector(ProxyAdmin.upgrade.selector, l2WethGateway, impl);
        vm.broadcast(deployerPrivateKey);
        upgradeExecutor.executeCall(address(proxyAdmin), upgradeCallData);
    }
}
