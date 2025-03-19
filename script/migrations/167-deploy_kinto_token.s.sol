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

    function run() public override {
        super.run();

        deployBridgedTokenNonKinto("K", "Kinto", 18, "010700", getMamoriSafeByChainId(block.chainid));
    }

    function deployBridgedTokenNonKinto(
        string memory symbol,
        string memory name,
        uint256 decimals,
        string memory startsWith,
        address admin
    ) internal {
        // deploy token
        bytes memory bytecode = abi.encodePacked(type(BridgedToken).creationCode, abi.encode(decimals));
        address implementation = _deployImplementation(name, "V1", bytecode, keccak256(abi.encodePacked(name, symbol)));

        bytes32 initCodeHash = keccak256(abi.encodePacked(type(UUPSProxy).creationCode, abi.encode(implementation, "")));
        (bytes32 salt, address expectedAddress) = mineSalt(initCodeHash, startsWith);

        address proxy = _deployProxy(name, implementation, salt);

        console2.log("Proxy deployed @%s", proxy);
        console2.log("Expected address: %s", expectedAddress);
        assertEq(proxy, expectedAddress);

        BridgedToken bridgedToken = BridgedToken(proxy);

        bridgedToken.initialize(name, symbol, admin, admin, admin);

        assertEq(bridgedToken.name(), name);
        assertEq(bridgedToken.symbol(), symbol);
        assertEq(bridgedToken.decimals(), decimals);
        assertTrue(bridgedToken.hasRole(bridgedToken.DEFAULT_ADMIN_ROLE(), admin), "Admin role not set");
        assertTrue(bridgedToken.hasRole(bridgedToken.MINTER_ROLE(), admin), "Minter role not set");
        assertTrue(bridgedToken.hasRole(bridgedToken.UPGRADER_ROLE(), admin), "Upgrader role not set");

        console2.log("All checks passed!");

        console2.log("%s implementation deployed @%s", symbol, implementation);
        console2.log("%s deployed @%s", symbol, address(bridgedToken));

        saveContractAddress(string.concat(symbol, "-impl"), implementation);
        saveContractAddress(symbol, address(bridgedToken));
    }
}
