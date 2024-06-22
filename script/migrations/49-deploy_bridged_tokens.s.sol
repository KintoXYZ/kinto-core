// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {LibString} from "solady/utils/LibString.sol";
import {ERC20} from "@openzeppelin-5.0.1/contracts/token/ERC20/ERC20.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {BridgedToken} from "../../src/tokens/bridged/BridgedToken.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import {UUPSProxy} from "@kinto-core-test/helpers/UUPSProxy.sol";
import {console2} from "forge-std/console2.sol";

contract KintoMigration49DeployScript is MigrationHelper {
    using LibString for *;
    using stdJson for string;

    uint256 mainnetFork = vm.createSelectFork("mainnet");
    uint256 kintoFork = vm.createSelectFork("kinto");

    address[] public bridgedTokens;

    // list of tokens we want to deploy as BridgedToken
    address[10] mainnetTokens = [
        // 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, // USDC (TBD if Circle token or Bridged Token)
        0x6B175474E89094C44Da98b954EedeAC495271d0F, // DAI
        0x83F20F44975D03b1b09e64809B757c47f942BEeA, // sDAI
        0x4c9EDD5852cd905f086C759E8383e09bff1E68B3, // USDe
        0x9D39A5DE30e57443BfF2A8307A4256c8797A3497, // sUSDe
        0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0, // wstETH
        0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee, // weETH
        0x57F5E098CaD7A3D1Eed53991D4d66C45C9AF7812, // wUSDM
        0x57e114B691Db790C35207b2e685D4A43181e6061, // ENA
        0x35fA164735182de50811E8e2E824cFb9B6118ac2, // eETH
        0xec53bF9167f50cDEB3Ae105f56099aaaB9061F83 // EIGEN
    ];

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
        for (uint256 i = 0; i < mainnetTokens.length; i++) {
            (string memory symbol, address bridgedToken, address impl) = deployBridgedToken(mainnetTokens[i]);
            bridgedTokens.push(bridgedToken);

            console2.log("%s implementation deployed @%s", symbol, impl);
            console2.log("%s deployed @%s", symbol, bridgedToken);

            saveContractAddress(string.concat(symbol, "-impl"), impl);
            saveContractAddress(symbol, bridgedToken);
        }
    }

    function checkToken(address token, string memory name, string memory symbol) internal view {
        BridgedToken bridgedToken = BridgedToken(token);
        require(keccak256(abi.encodePacked(bridgedToken.name())) == keccak256(abi.encodePacked(name)), "Name mismatch");
        require(
            keccak256(abi.encodePacked(bridgedToken.symbol())) == keccak256(abi.encodePacked(symbol)), "Symbol mismatch"
        );
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
        string memory name;

        // special case for ENA since it's deployed on shanghai version
        if (token == 0x57e114B691Db790C35207b2e685D4A43181e6061) {
            name = "ENA";
            symbol = "ENA";
        } else {
            name = ERC20(token).name();
            symbol = ERC20(token).symbol();
            require(ERC20(token).decimals() == 18, "Decimals must be 18");
        }
        console2.log("Deploying BridgedToken for %s", name);

        // switch back to Kinto fork
        vm.selectFork(kintoFork);

        // deploy token
        bytes memory bytecode = abi.encodePacked(type(BridgedToken).creationCode);
        implementation = _deployImplementation("BridgedToken", "V1", bytecode, keccak256(abi.encodePacked(symbol)));

        bytes32 initCodeHash = keccak256(abi.encodePacked(type(UUPSProxy).creationCode, abi.encode(implementation, "")));
        (bytes32 salt, address expectedAddress) = mineSalt(initCodeHash, getSalt(symbol));

        proxy = _deployProxy("BridgedToken", implementation, salt);

        assertEq(proxy, expectedAddress);

        _whitelistApp(proxy);

        // initialize
        bytes memory selectorAndParams =
            abi.encodeWithSelector(BridgedToken.initialize.selector, name, symbol, admin, minter, upgrader);
        _handleOps(selectorAndParams, proxy, deployerPrivateKey);

        checkToken(proxy, name, symbol);
    }

    function getSalt(string memory symbol) internal pure returns (string memory) {
        // https://en.wikipedia.org/wiki/Leet
        if (symbol.eqs("USDe")) {
            return "05De00";
        }
        if (symbol.eqs("sUSDe")) {
            return "505De0";
        }
        if (symbol.eqs("wstETH")) {
            return "057E70";
        }
        if (symbol.eqs("weETH")) {
            return "0eE700";
        }
        if (symbol.eqs("wUSDM")) {
            return "005011";
        }
        if (symbol.eqs("ENA")) {
            return "E04000";
        }
        if (symbol.eqs("eETH")) {
            return "eE7000";
        }
        if (symbol.eqs("EIGEN")) {
            return "E16E00";
        }
        if (symbol.eqs("DAI")) {
            return "DA1000";
        }
        if (symbol.eqs("sDAI")) {
            return "5DA100";
        }
        return "000000";
    }
}
