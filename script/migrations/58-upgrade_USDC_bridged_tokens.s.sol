// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {LibString} from "solady/utils/LibString.sol";
import {ERC20} from "@openzeppelin-5.0.1/contracts/token/ERC20/ERC20.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {BridgedToken} from "../../src/tokens/bridged/BridgedToken.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import {UUPSProxy} from "@kinto-core-test/helpers/UUPSProxy.sol";
import {console2} from "forge-std/console2.sol";

contract KintoMigration58DeployScript is MigrationHelper {
    using LibString for *;
    using stdJson for string;

    uint256 mainnetFork = vm.createSelectFork("mainnet");
    uint256 kintoFork = vm.createSelectFork("kinto");

    // list of tokens we want to deploy as BridgedToken
    address USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC

    // KINTO_WALLET will be the admin, minter and upgrader of every BridgedToken
    address kintoWallet = vm.envAddress("ADMIN_KINTO_WALLET");
    address admin = kintoWallet;
    address minter = admin;
    address upgrader = admin;

    function run() public override {
        super.run();
        deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        broadcast();
    }

    function broadcast() internal {
        (string memory symbol, address bridgedToken, address impl) = deployBridgedToken(USDC);

        console2.log("%s implementation deployed @%s", symbol, impl);
        console2.log("%s deployed @%s", symbol, bridgedToken);

        saveContractAddress(string.concat(symbol, "V2", "-impl"), impl);
        saveContractAddress(symbol, bridgedToken);
    }

    function checkToken(address token, string memory name, string memory symbol) internal view {
        BridgedToken bridgedToken = BridgedToken(token);
        require(keccak256(abi.encodePacked(bridgedToken.name())) == keccak256(abi.encodePacked(name)), "Name mismatch");
        require(
            keccak256(abi.encodePacked(bridgedToken.symbol())) == keccak256(abi.encodePacked(symbol)), "Symbol mismatch"
        );
        require(bridgedToken.decimals() == 6, "Decimals mismatch");
        require(bridgedToken.hasRole(bridgedToken.DEFAULT_ADMIN_ROLE(), admin), "Admin role not set");
        require(bridgedToken.hasRole(bridgedToken.MINTER_ROLE(), minter), "Minter role not set");
        require(bridgedToken.hasRole(bridgedToken.UPGRADER_ROLE(), upgrader), "Upgrader role not set");
        console2.log("All checks passed!");
    }

    // deploys a bridged token, whitelists and initialises it
    function deployBridgedToken(address token)
        public
        returns (string memory symbol, address proxy, address implementation)
    {
        // read token info from mainnet fork
        vm.selectFork(mainnetFork);
        string memory name = ERC20(token).name();
        symbol = ERC20(token).symbol();
        console2.log("Deploying BridgedToken for %s", name);

        // switch back to Kinto fork
        vm.selectFork(kintoFork);

        // deploy token
        bytes memory bytecode = abi.encodePacked(type(BridgedToken).creationCode, abi.encode(6));
        proxy = _getChainDeployment("USDC");
        implementation = _deployImplementationAndUpgrade("USDC", "V2", bytecode);

        checkToken(proxy, name, symbol);
    }
}
