// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {LibString} from "solady/utils/LibString.sol";
import {ERC20} from "@openzeppelin-5.0.1/contracts/token/ERC20/ERC20.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {BridgedToken} from "../../src/tokens/bridged/BridgedToken.sol";
import {IKintoWallet} from "../../src/interfaces/IKintoWallet.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import {UUPSProxy} from "@kinto-core-test/helpers/UUPSProxy.sol";
import {console2} from "forge-std/console2.sol";

contract KintoMigration60DeployScript is MigrationHelper {
    using LibString for *;
    using stdJson for string;

    uint256 mainnetFork = vm.createSelectFork("arbitrum");
    uint256 kintoFork = vm.createSelectFork("kinto");

    // list of tokens we want to deploy as BridgedToken
    address SolvBTC = 0x3647c54c4c2C65bC7a2D63c0Da2809B399DBBDC0; // SolvBTC

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
        (string memory symbol, address bridgedToken, address impl) = deployBridgedToken(SolvBTC);

        console2.log("%s implementation deployed @%s", symbol, impl);
        console2.log("%s deployed @%s", symbol, bridgedToken);

        saveContractAddress(string.concat(symbol, "-impl"), impl);
        saveContractAddress(symbol, bridgedToken);
    }

    function checkToken(address token, string memory name, string memory symbol) internal view {
        BridgedToken bridgedToken = BridgedToken(token);
        require(keccak256(abi.encodePacked(bridgedToken.name())) == keccak256(abi.encodePacked(name)), "Name mismatch");
        require(
            keccak256(abi.encodePacked(bridgedToken.symbol())) == keccak256(abi.encodePacked(symbol)), "Symbol mismatch"
        );
        // assert name is symbol is ETFI
        require(bridgedToken.decimals() == 18, "Decimals mismatch");
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
        uint8 decimals = ERC20(token).decimals();
        console2.log("Deploying BridgedToken for %s", name);

        // switch back to Kinto fork
        vm.selectFork(kintoFork);

        // deploy token
        bytes memory bytecode = abi.encodePacked(type(BridgedToken).creationCode, abi.encode(decimals));
        implementation = _deployImplementation("BridgedToken", "V1", bytecode, keccak256(abi.encodePacked(symbol)));

        bytes32 initCodeHash = keccak256(abi.encodePacked(type(UUPSProxy).creationCode, abi.encode(implementation, "")));
        (bytes32 salt, address expectedAddress) = mineSalt(initCodeHash, "501B7C");

        proxy = _deployProxy("BridgedToken", implementation, salt);

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
                abi.encodeWithSelector(BridgedToken.initialize.selector, name, symbol, admin, minter, upgrader);
            _handleOps(selectorAndParams, wallet, proxy, 0, address(0), privKeys);
        }

        checkToken(proxy, name, symbol);
    }
}
