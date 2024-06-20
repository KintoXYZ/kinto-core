// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {console2} from "forge-std/console2.sol";
import {Script} from "forge-std/Script.sol";

import {BridgedToken} from "@kinto-core/tokens/bridged/BridgedToken.sol";
import {BridgedWeth} from "@kinto-core/tokens/bridged/BridgedWeth.sol";
import {UUPSUpgradeable} from "@openzeppelin-5.0.1/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {IKintoWallet} from "@kinto-core/interfaces/IKintoWallet.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";

contract UpgradeBridgedWethScript is MigrationHelper {
    BridgedWeth weth;

    function run() public override {
        super.run();

        IKintoWallet adminWallet = IKintoWallet(_getChainDeployment("KintoWallet-admin"));
        weth = BridgedWeth(payable(_getChainDeployment("WETH")));
        if (address(weth) == address(0)) {
            console2.log("WETH has to be deployed");
            return;
        }

        // etchWallet(0xe1FcA7f6d88E30914089b600A73eeF72eaC7f601);
        // replaceOwner(adminWallet, 0x4632F4120DC68F225e7d24d973Ee57478389e9Fd);

        vm.broadcast(deployerPrivateKey);
        BridgedWeth newImpl =
            BridgedWeth(payable(create2(abi.encodePacked(type(BridgedWeth).creationCode, abi.encode(18)))));

        uint256[] memory privKeys = new uint256[](1);
        privKeys[0] = deployerPrivateKey;
        _handleOps(
            abi.encodeWithSelector(UUPSUpgradeable.upgradeToAndCall.selector, newImpl, bytes("")),
            address(adminWallet),
            address(weth),
            0,
            address(0),
            privKeys
        );

        weth.deposit{value: 1}();
        require(weth.balanceOf(address(this)) == 1, "WETH deposit failed");
        assertEq(weth.name(), "Wrapped Ether");
        assertEq(weth.symbol(), "WETH");
    }
}
