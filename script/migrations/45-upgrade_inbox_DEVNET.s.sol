// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import "../../src/wallet/KintoWalletFactory.sol";
import "../../src/nitro-contracts/bridge/AbsInbox.sol";
import "../../src/nitro-contracts/bridge/Inbox.sol";
import "@kinto-core-script/utils/MigrationHelper.sol";
import {L1GatewayRouter} from "@token-bridge-contracts/contracts/tokenbridge/ethereum/gateway/L1GatewayRouter.sol";

interface IUpgradeExecutor {
    function initialize(address admin, address[] memory executors) external;
    function execute(address upgrade, bytes memory upgradeCallData) external payable;
    function executeCall(address target, bytes memory targetCallData) external payable;
    function hasRole(bytes32 role, address account) external view returns (bool);
}

contract KintoMigration45DeployScript is MigrationHelper {
    using ECDSAUpgradeable for bytes32;

    function run() public override {
        vm.setEnv("PRIVATE_KEY", vm.toString(vm.envUint("TEST_PRIVATE_KEY")));
        super.run();

        TransparentUpgradeableProxy inbox =
            TransparentUpgradeableProxy(payable(0x56Aa813046CC0DeFd7Afba2a2812527Bb9bCDf4b)); // sepolia
        ProxyAdmin proxyAdmin = ProxyAdmin(0xe831A07bd80c5373DB90692eb104F60e5823a66F); // sepolia
        IUpgradeExecutor upgradeExecutor = IUpgradeExecutor(0xa8f2c4EC5834aaF1D12ab595eF389F829CF4e3AE); // sepolia

        if (!upgradeExecutor.hasRole(keccak256("EXECUTOR_ROLE"), vm.addr(deployerPrivateKey))) {
            revert("Sender does not have EXECUTOR_ROLE");
        }

        // upgrade Inbox
        uint256 maxDataSize = AbsInbox(address(inbox)).maxDataSize();
        vm.broadcast(deployerPrivateKey);
        address impl = address(new Inbox(maxDataSize));
        console.log("InboxV2-impl: ", impl);
        bytes memory upgradeCallData = abi.encodeWithSelector(ProxyAdmin.upgrade.selector, inbox, impl);

        vm.broadcast(deployerPrivateKey);
        upgradeExecutor.executeCall(address(proxyAdmin), upgradeCallData);

        // function below no longer exists
        // vm.broadcast(deployerPrivateKey);
        // AbsInbox(address(inbox)).initializeL2AllowList();

        // vm.broadcast(deployerPrivateKey);
        // L1GatewayRouter(0xbEB11D12972C11319fF8742a28D361763f2858a9).outboundTransfer{value: 38674917993600}(
        //     0x88541670E55cC00bEEFD87eB59EDd1b7C511AC9a,
        //     0x1dBDF0936dF26Ba3D7e4bAA6297da9FE2d2428c2,
        //     1000000000000000000,
        //     7894700,
        //     3000000,
        //     abi.encode(3525570487760, "", 0)
        // );
    }
}
