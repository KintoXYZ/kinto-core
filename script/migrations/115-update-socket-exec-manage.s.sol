// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {LibString} from "solady/utils/LibString.sol";
import {ERC20} from "@openzeppelin-5.0.1/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin-5.0.1/contracts/interfaces/IERC20.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {IAccessControl} from "@openzeppelin-5.0.1/contracts/access/IAccessControl.sol";
import {IKintoWallet} from "@kinto-core/interfaces/IKintoWallet.sol";
import {RewardsDistributor} from "@kinto-core/liquidity-mining/RewardsDistributor.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import {console2} from "forge-std/console2.sol";

interface ISocket {
    function setExecutionManager(address executionManager) external;

    function executionManager__() external view returns (address);
}

contract Script is MigrationHelper {
    using LibString for *;
    using Strings for string;
    using stdJson for string;

    function run() public override {
        super.run();

        address SOCKET = 0x3e9727470C66B1e77034590926CDe0242B5A3dCc;
        address EXECUTION_MANAGER = 0xc8a4D2fd77c155fd52e65Ab07F337aBF84495Ead;

        _handleOps(abi.encodeWithSelector(ISocket.setExecutionManager.selector, EXECUTION_MANAGER), SOCKET);

        assertEq(ISocket(SOCKET).executionManager__(), EXECUTION_MANAGER);
    }
}
