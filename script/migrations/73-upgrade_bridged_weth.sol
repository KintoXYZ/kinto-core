// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {console2} from "forge-std/console2.sol";
import {Script} from "forge-std/Script.sol";

import {BridgedToken} from "@kinto-core/tokens/BridgedToken.sol";
import {BridgedWeth} from "@kinto-core/tokens/BridgedWeth.sol";
import {UUPSUpgradeable} from "@openzeppelin-5.0.1/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import "@kinto-core-script/migrations/const.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";

contract UpgradeBridgedWethScript is MigrationHelper, Constants {
    BridgedWeth weth;

    function deployContracts(address) internal override {
        weth = BridgedWeth(payable(_getChainDeployment("WETH")));
        if (address(weth) == address(0)) {
            console2.log("WETH has to be deployed");
            return;
        }

        BridgedWeth newImpl = BridgedWeth(
            payable(create2("BridgedWethV1-impl", abi.encodePacked(type(BridgedWeth).creationCode, abi.encode(18))))
        );

        uint256[] memory privKeys = new uint256[](2);
        privKeys[0] = deployerPrivateKey;
        privKeys[1] = LEDGER;
        console2.log('private keys');
        console2.log(privKeys[0]);
        console2.log(privKeys[1]);
        _handleOps(
            abi.encodeWithSelector(UUPSUpgradeable.upgradeToAndCall.selector, newImpl, bytes("")),
            _getChainDeployment("KintoWallet-admin"),
            address(weth),
            address(0),
            privKeys
        );
    }

    function checkContracts(address) internal override {
        weth.deposit{value: 1}();
        require(weth.balanceOf(address(this)) == 1, "WETH deposit failed");
        assertEq(weth.name(), "Wrapped Ether");
        assertEq(weth.symbol(), "WETH");
    }
}
