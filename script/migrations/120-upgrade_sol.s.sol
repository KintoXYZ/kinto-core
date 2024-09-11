// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {console2} from "forge-std/console2.sol";
import {Script} from "forge-std/Script.sol";

import {BridgedToken} from "@kinto-core/tokens/bridged/BridgedToken.sol";
import {BridgedSol} from "@kinto-core/tokens/bridged/BridgedSol.sol";
import {UUPSUpgradeable} from "@openzeppelin-5.0.1/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {IKintoWallet} from "@kinto-core/interfaces/IKintoWallet.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";

contract UpgradeBridgedSolScript is MigrationHelper {
    BridgedSol sol;

    function run() public override {
        super.run();

        IKintoWallet adminWallet = IKintoWallet(_getChainDeployment("KintoWallet-admin"));
        sol = BridgedSol(payable(_getChainDeployment("SOL")));
        if (address(sol) == address(0)) {
            console2.log("SOL has to be deployed");
            return;
        }

        vm.broadcast(deployerPrivateKey);
        BridgedSol newImpl =
            BridgedSol(payable(create2(abi.encodePacked(type(BridgedSol).creationCode))));

        uint256[] memory privKeys = new uint256[](1);
        privKeys[0] = deployerPrivateKey;
        _handleOps(
            abi.encodeWithSelector(UUPSUpgradeable.upgradeToAndCall.selector, newImpl, bytes("")),
            address(adminWallet),
            address(sol),
            0,
            address(0),
            privKeys
        );

        require(weth.deciamls() == 9, "SOL upgrade failed");
    }
}
