// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {LibString} from "solady/utils/LibString.sol";
import {ERC20} from "@openzeppelin-5.0.1/contracts/token/ERC20/ERC20.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {BridgedToken} from "@kinto-core/tokens/bridged/BridgedToken.sol";
import {BridgedKinto} from "@kinto-core/tokens/bridged/BridgedKinto.sol";
import {IKintoWallet} from "@kinto-core/interfaces/IKintoWallet.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import {UUPSProxy} from "@kinto-core-test/helpers/UUPSProxy.sol";
import {console2} from "forge-std/console2.sol";

contract DeployKintoScript is MigrationHelper {
    using LibString for *;
    using Strings for string;
    using stdJson for string;

    // KINTO_WALLET will be the admin, minter and upgrader of every BridgedKinto
    address kintoWallet = vm.envAddress("ADMIN_KINTO_WALLET");
    address admin = kintoWallet;
    address minter = admin;
    address upgrader = admin;

    function run() public override {
        super.run();

        string memory symbol = 'KINTO';
        string memory name = 'Kinto Token';

        // deploy token
        bytes memory bytecode = abi.encodePacked(type(BridgedKinto).creationCode);
        address implementation = _deployImplementation("BridgedKinto", "V1", bytecode, keccak256(abi.encodePacked(symbol)));

        bytes32 initCodeHash = keccak256(abi.encodePacked(type(UUPSProxy).creationCode, abi.encode(implementation, "")));
        (bytes32 salt, address expectedAddress) = mineSalt(initCodeHash, "010700");

        address proxy = _deployProxy("BridgedKinto", implementation, salt);

        console2.log("Proxy deployed @%s", proxy);
        console2.log("Expected address: %s", expectedAddress);
        assertEq(proxy, expectedAddress);

        {
            // whitelist app & initialize
            address wallet = 0x7403542bF2aF061eBF0DC16cAfA3068b90Fc1e75; // fede's kinto wallet
            uint256[] memory privKeys = new uint256[](1);
            privKeys[0] = deployerPrivateKey;

            // whitelist
            address[] memory apps = new address[](1);
            apps[0] = proxy;
            bool[] memory flags = new bool[](1);
            flags[0] = true;
            bytes memory selectorAndParams = abi.encodeWithSelector(IKintoWallet.whitelistApp.selector, apps, flags);
            _handleOps(selectorAndParams, wallet, wallet, 0, address(0), privKeys);

            // initialize
            privKeys = new uint256[](2);
            privKeys[0] = deployerPrivateKey;
            privKeys[1] = LEDGER;

            selectorAndParams =
                abi.encodeWithSelector(BridgedToken.initialize.selector, name, symbol, admin, admin, admin);
            _handleOps(selectorAndParams, wallet, proxy, 0, address(0), privKeys);
        }

        BridgedKinto bridgedToken = BridgedKinto(proxy);

        require(bridgedToken.name().equal("Kinto Token"), "");
        require(bridgedToken.symbol().equal("KINTO"), "");
        require(bridgedToken.decimals() == 18, "");
        require(bridgedToken.hasRole(bridgedToken.DEFAULT_ADMIN_ROLE(), admin), "Admin role not set");
        require(bridgedToken.hasRole(bridgedToken.MINTER_ROLE(), admin), "Minter role not set");
        require(bridgedToken.hasRole(bridgedToken.UPGRADER_ROLE(), admin), "Upgrader role not set");

        console2.log("All checks passed!");

        console2.log("%s implementation deployed @%s", symbol, implementation);
        console2.log("%s deployed @%s", symbol, address(bridgedToken));

        saveContractAddress(string.concat(symbol, "-impl"), implementation);
        saveContractAddress(symbol, address(bridgedToken));
    }
}
