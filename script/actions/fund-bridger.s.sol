// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {KintoWalletFactory} from "@kinto-core/wallet/KintoWalletFactory.sol";
import {SponsorPaymaster} from "@kinto-core/paymasters/SponsorPaymaster.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import {ArrayHelpers} from "@kinto-core-test/helpers/ArrayHelpers.sol";
import "forge-std/console2.sol";

contract FundBridgerScript is MigrationHelper {
    using ArrayHelpers for *;

    address public constant ETHEREUM_BRIDGER = 0x0f1b7bd7762662B23486320AA91F30312184f70C;
    address public constant ARB_BRIDGER = 0xb7DfE09Cf3950141DFb7DB8ABca90dDef8d06Ec0;
    address public constant BASE_BRIDGER = 0x361C9A99Cf874ec0B0A0A89e217Bf0264ee17a5B;

    function run() public override {
        super.run();

        console2.log("Hot Wallet Balance: %e", deployer.balance);
        if (deployer.balance < 0.25 ether) {
            console2.log("Hot Wallet Balance too low. Refill.");
            return;
        }

        console2.log("");
        console2.log("Bridgers");

        address[3] memory bridgers = [ETHEREUM_BRIDGER, ARB_BRIDGER, BASE_BRIDGER];

        if(block.chainid == ETHEREUM_CHAINID) {
            fund(ETHEREUM_BRIDGER, "ETHEREUM_BRIDGER", 0.25 ether, 0.25 ether);
        }

        if(block.chainid == ARBITRUM_CHAINID) {
            fund(ARB_BRIDGER, "ARB_BRIDGER", 0.25 ether, 0.25 ether);
        }

        if(block.chainid == BASE_CHAINID) {
            fund(BASE_BRIDGER, "BASE_BRIDGER", 0.25 ether, 0.25 ether);
        }

        for (uint256 index = 0; index < bridgers.length; index++) {
        }
    }

    function fund(address bridger, string memory name, uint256 limit, uint256 amount) internal {
            uint256 balance = bridger.balance;
            console2.log("bridger:", name);
            console2.log("Address:", bridger);
            console2.log("Balance: %e", balance);

            if (balance < limit) {
                console2.log("Needs funding. Adding: %e", amount);

                vm.broadcast(deployerPrivateKey);
                (bool success,) = address(bridger).call{value: amount}("");
                require(success, "Failed to send ETH");
            }

    }
}
