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

contract KintoMigration49DeployScript is MigrationHelper {
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
        console2.log("InboxV3-impl: ", impl);

        // upgrade Inbox (only from multisig)
        if (!upgradeExecutor.hasRole(keccak256("EXECUTOR_ROLE"), msg.sender)) {
            console2.log("Sender does not have EXECUTOR_ROLE");
            return;
        }

        bytes memory upgradeCallData = abi.encodeWithSelector(ProxyAdmin.upgrade.selector, inbox, impl);
        vm.prank(0x17Eb10e12a78f986C78F973Fc70eD88072B33B7d);
        upgradeExecutor.executeCall(address(proxyAdmin), upgradeCallData);

        address[] memory users = new address[](8);
        users[0] = 0x06FcD8264caF5c28D86eb4630c20004aa1faAaA8; // L2 customGateway
        users[1] = 0x340487b92808B84c2bd97C87B590EE81267E04a7; // L2 router
        users[2] = 0x87799989341A07F495287B1433eea98398FD73aA; // L2 standardGateway
        users[3] = 0xd563ECBDF90EBA783d0a218EFf158C1263ad02BE; // L2 wethGateway

        users[4] = 0x094F8C3eA1b5671dd19E15eCD93C80d2A33fCA99; // L2 customGateway (devnet)
        users[5] = 0xf3AC740Fcc64eEd76dFaE663807749189A332d54; // L2 router (devnet)
        users[6] = 0x6A8d32c495df943212B7788114e41103047150a5; // L2 standardGateway (devnet)
        users[7] = 0x79B47F0695608aD8dc90E400a3E123b02eB72D24; // L2 wethGateway (devnet)

        bool[] memory values = new bool[](8);
        values[0] = true;
        values[1] = true;
        values[2] = true;
        values[3] = true;

        values[4] = false;
        values[5] = false;
        values[6] = false;
        values[7] = false;

        upgradeCallData = abi.encodeWithSelector(AbsInbox.setL2AllowList.selector, users, values);
        vm.prank(0x17Eb10e12a78f986C78F973Fc70eD88072B33B7d);
        upgradeExecutor.executeCall(address(inbox), upgradeCallData);
    }
}
