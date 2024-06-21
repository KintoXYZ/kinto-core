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

contract InitKintoScript {
    constructor(BridgedToken token, string memory name, string memory symbol, address adminWallet) {
        token.initialize(name, symbol, adminWallet, adminWallet, adminWallet);
    }
}

contract DeployKintoScript is MigrationHelper {
    using LibString for *;
    using Strings for string;
    using stdJson for string;

    function run() public override {
        super.run();

        address adminWallet = _getChainDeployment("KintoWallet-admin");

        string memory symbol = "KINTO";
        string memory name = "Kinto Token";

        // deploy token
        bytes memory bytecode = abi.encodePacked(type(BridgedKinto).creationCode);
        address implementation =
            _deployImplementation("BridgedKinto", "V1", bytecode, keccak256(abi.encodePacked(symbol)));

        bytes32 initCodeHash = keccak256(abi.encodePacked(type(UUPSProxy).creationCode, abi.encode(implementation, "")));
        (bytes32 salt, address expectedAddress) = mineSalt(initCodeHash, "010700");

        address proxy = _deployProxy("BridgedKinto", implementation, salt);

        console2.log("Proxy deployed @%s", proxy);
        console2.log("Expected address: %s", expectedAddress);
        assertEq(proxy, expectedAddress);

        vm.broadcast(deployerPrivateKey);
        create2(abi.encodePacked(type(InitKintoScript).creationCode, abi.encode(proxy, name, symbol, adminWallet)));

        BridgedKinto bridgedToken = BridgedKinto(proxy);

        require(bridgedToken.name().equal("Kinto Token"), "");
        require(bridgedToken.symbol().equal("KINTO"), "");
        require(bridgedToken.decimals() == 18, "");
        require(bridgedToken.hasRole(bridgedToken.DEFAULT_ADMIN_ROLE(), adminWallet), "adminWallet role not set");
        require(bridgedToken.hasRole(bridgedToken.MINTER_ROLE(), adminWallet), "Minter role not set");
        require(bridgedToken.hasRole(bridgedToken.UPGRADER_ROLE(), adminWallet), "Upgrader role not set");

        console2.log("All checks passed!");

        console2.log("%s implementation deployed @%s", symbol, implementation);
        console2.log("%s deployed @%s", symbol, address(bridgedToken));

        saveContractAddress(string.concat(symbol, "-impl"), implementation);
        saveContractAddress(symbol, address(bridgedToken));
    }
}
