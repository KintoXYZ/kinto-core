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

contract KintoMigration42DeployScript is MigrationHelper {
    function run() public override {
        super.run();

        TransparentUpgradeableProxy l2CustomGateway =
            TransparentUpgradeableProxy(payable(0x06FcD8264caF5c28D86eb4630c20004aa1faAaA8));
        TransparentUpgradeableProxy l2ERC20Gateway =
            TransparentUpgradeableProxy(payable(0x87799989341A07F495287B1433eea98398FD73aA));
        TransparentUpgradeableProxy l2WethGateway =
            TransparentUpgradeableProxy(payable(0xd563ECBDF90EBA783d0a218EFf158C1263ad02BE));
        ProxyAdmin proxyAdmin = ProxyAdmin(0x9eC0253E4174a14C0536261888416451A407Bf79);
        IUpgradeExecutor upgradeExecutor = IUpgradeExecutor(0x88e03D41a6EAA9A0B93B0e2d6F1B34619cC4319b);

        console2.log("msg.sender: %s", msg.sender);
        if (!upgradeExecutor.hasRole(keccak256("EXECUTOR_ROLE"), msg.sender)) {
            revert("Sender does not have EXECUTOR_ROLE");
        }

        // L2CustomGateway
        bytes memory bytecode = abi.encodePacked(type(L2CustomGateway).creationCode);
        address impl = _deployImplementation("L2CustomGateway", "V2", bytecode);
        bytes memory upgradeCallData = abi.encodeWithSelector(ProxyAdmin.upgrade.selector, l2CustomGateway, impl);
        vm.broadcast();
        upgradeExecutor.executeCall(address(proxyAdmin), upgradeCallData);

        // L2ERC20Gateway
        bytecode = abi.encodePacked(type(L2ERC20Gateway).creationCode);
        impl = _deployImplementation("L2ERC20Gateway", "V2", bytecode);
        upgradeCallData = abi.encodeWithSelector(ProxyAdmin.upgrade.selector, l2ERC20Gateway, impl);
        vm.broadcast();
        upgradeExecutor.executeCall(address(proxyAdmin), upgradeCallData);

        // L2WethGateway
        bytecode = abi.encodePacked(type(L2WethGateway).creationCode);
        impl = _deployImplementation("L2WethGateway", "V2", bytecode);
        upgradeCallData = abi.encodeWithSelector(ProxyAdmin.upgrade.selector, l2WethGateway, impl);
        vm.broadcast();
        upgradeExecutor.executeCall(address(proxyAdmin), upgradeCallData);
    }
}
