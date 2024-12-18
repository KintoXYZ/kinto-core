// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../../src/wallet/KintoWalletFactory.sol";
import "../../src/bridger/BridgerL2.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";

contract KintoMigration41DeployScript is MigrationHelper {
    function run() public override {
        super.run();
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        BridgerL2 bridgerL2 = BridgerL2(_getChainDeployment("BridgerL2"));
        address[] memory bridgerL2Assets = new address[](4);
        bridgerL2Assets[0] = 0x4190A8ABDe37c9A85fAC181037844615BA934711; // sDAI
        bridgerL2Assets[1] = 0xF4d81A46cc3fCA44f88d87912A35E7fCC4B398ee; // sUSDe
        bridgerL2Assets[2] = 0x6e316425A25D2Cf15fb04BCD3eE7c6325B240200; // wstETH
        bridgerL2Assets[3] = 0xC60F14d95B87417BfD17a376276DE15bE7171d31; // weETH
        _fundPaymaster(address(bridgerL2), deployerPrivateKey);
        _whitelistApp(address(bridgerL2));
        _handleOps(
            abi.encodeWithSelector(BridgerL2.setDepositedAssets.selector, bridgerL2Assets),
            address(bridgerL2),
            deployerPrivateKey
        );
        assertEq(bridgerL2.owner(), _getChainDeployment("KintoWallet-admin"));
        assertEq(bridgerL2.depositedAssets(0), bridgerL2Assets[0]);
        assertEq(bridgerL2.depositedAssets(1), bridgerL2Assets[1]);
        assertEq(bridgerL2.depositedAssets(2), bridgerL2Assets[2]);
        assertEq(bridgerL2.depositedAssets(3), bridgerL2Assets[3]);
    }
}
