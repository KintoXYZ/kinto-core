// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {IERC20} from "@openzeppelin-5.0.1/contracts/token/ERC20/IERC20.sol";
import {IBridge} from "@kinto-core/socket/IBridge.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";

import "forge-std/Script.sol";
import "forge-std/console.sol";

contract BridgeKintoTokenScript is MigrationHelper {
    // Constants
    address public constant KINTO_TOKEN = 0x010700808D59d2bb92257fCafACfe8e5bFF7aB87;
    uint256 public constant MAX_UINT = type(uint256).max;

    // Hardcoded values
    address public constant KINTO_ADMIN = 0x2e2B1c42E38f5af81771e65D87729E57ABD1337a;
    address public constant SOCKET_VAULT = 0x3De040ef2Fbf9158BADF559C5606d7706ca72309;
    address public constant RECEIVER = 0x660ad4B5A74130a4796B4d54BC6750Ae93C86e6c;
    uint256 public constant AMOUNT = 1_000 * 1e18; // 1_000 KINTO tokens
    uint256 public constant MSG_GAS_LIMIT = 500000;
    address public constant CONNECTOR = 0xbef01d401b54C19B2bcFe93f5e55e0355fE24A73;
    bytes public constant EXEC_PAYLOAD = "";
    bytes public constant OPTIONS = "";
    uint256 public constant GAS_FEE = 1 ether / 1000; // 0.001 ETH

    function run() public override {
        super.run();

        console.log("Setting infinite allowance for Socket Vault");
        console.log("KintoAdmin:", KINTO_ADMIN);
        console.log("Socket Vault:", SOCKET_VAULT);
        console.log("Amount to bridge:", AMOUNT);

        // Bridge the tokens using the KintoAdmin wallet
        console.log("Bridging tokens to Ethereum");
        console.log("Receiver:", RECEIVER);
        console.log("Connector:", CONNECTOR);

        uint256[] memory privKeys = new uint256[](2);
        privKeys[0] = deployerPrivateKey;
        privKeys[1] = hardwareWalletType;
        _handleOps(
            abi.encodeWithSelector(
                IBridge.bridge.selector, RECEIVER, AMOUNT, MSG_GAS_LIMIT, CONNECTOR, EXEC_PAYLOAD, OPTIONS
            ),
            KINTO_ADMIN,
            SOCKET_VAULT,
            GAS_FEE,
            address(0),
            privKeys
        );

        console.log("Tokens bridged successfully!");
    }
}
