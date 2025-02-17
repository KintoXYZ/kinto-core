// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {ArrayHelpers} from "@kinto-core-test/helpers/ArrayHelpers.sol";
import {LibString} from "solady/utils/LibString.sol";
import {ERC20} from "@openzeppelin-5.0.1/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin-5.0.1/contracts/interfaces/IERC20.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {IKintoWallet} from "@kinto-core/interfaces/IKintoWallet.sol";
import {BridgerL2} from "@kinto-core/bridger/BridgerL2.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import {UUPSProxy} from "@kinto-core-test/helpers/UUPSProxy.sol";
import {console2} from "forge-std/console2.sol";

contract Script is MigrationHelper {
    using ArrayHelpers for *;
    using LibString for *;
    using Strings for string;
    using stdJson for string;

    function run() public override {
        super.run();

        address bridgerL2 = 0x26181Dfc530d96523350e895180b09BAf3d816a0;
        address miningAdaptor = 0xa5e9f2dd08582bBe2D41FAd465Cf8feCbFcbF6F3;
        address rewardsDistributor = 0xD157904639E89df05e89e0DabeEC99aE3d74F9AA;

        _whitelistApp(bridgerL2);

        _handleOps(abi.encodeWithSelector(BridgerL2.setReceiver.selector, [rewardsDistributor].toMemoryArray(), [true].toMemoryArray()), bridgerL2, deployerPrivateKey);

        _handleOps(abi.encodeWithSelector(BridgerL2.setSender.selector, [miningAdaptor].toMemoryArray(), [true].toMemoryArray()), bridgerL2, deployerPrivateKey);

    }
}
