// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {LibString} from "solady/utils/LibString.sol";
import {ERC20} from "@openzeppelin-5.0.1/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin-5.0.1/contracts/interfaces/IERC20.sol";
import {ERC1967Proxy} from "@openzeppelin-5.0.1/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {IKintoWallet} from "@kinto-core/interfaces/IKintoWallet.sol";
import {Treasury} from "@kinto-core/treasury/Treasury.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";

import {console2} from "forge-std/console2.sol";

contract DeployTreasuryScript is MigrationHelper {
    using LibString for *;
    using Strings for string;
    using stdJson for string;

    function run() public override {
        super.run();

        vm.broadcast(deployerPrivateKey);
        address impl = address(new Treasury{salt: keccak256("0")}());

        bytes32 initCodeHash = keccak256(abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(impl, "")));
        (bytes32 salt, address expectedAddress) = mineSalt(initCodeHash, "793500");

        vm.broadcast(deployerPrivateKey);
        address proxy = address(new ERC1967Proxy{salt: salt}(address(impl), ""));

        _whitelistApp(proxy);

        _handleOps(abi.encodeWithSelector(Treasury.initialize.selector), proxy);

        console2.log("Proxy deployed @%s", proxy);

        assertEq(proxy, expectedAddress);

        console2.log("All checks passed!");

        saveContractAddress(string.concat("Treasury", "-impl"), impl);
        saveContractAddress("Treasury", proxy);
    }
}
