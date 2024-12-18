// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {console2} from "forge-std/console2.sol";
import {Script} from "forge-std/Script.sol";

import {BridgedToken} from "@kinto-core/tokens/bridged/BridgedToken.sol";
import {BridgedSol} from "@kinto-core/tokens/bridged/BridgedSol.sol";
import {UUPSUpgradeable} from "@openzeppelin-5.0.1/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {IKintoWallet} from "@kinto-core/interfaces/IKintoWallet.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";

contract MigrationScript is MigrationHelper {
    function run() public override {
        super.run();

        address[] memory funders = new address[](1);
        // access point address for KintoAdmin
        funders[0] = address(0x474ec69B0fD5Ebc1EfcFe18B2E8Eb510D755b8C7);

        bool[] memory flags = new bool[](1);
        flags[0] = true;

        _handleOps(abi.encodeWithSignature("setFunderWhitelist(address[],bool[])", funders, flags), kintoAdminWallet);

        assertTrue(IKintoWallet(kintoAdminWallet).funderWhitelist(funders[0]));
    }
}
