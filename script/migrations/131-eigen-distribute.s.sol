// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../../src/wallet/KintoWalletFactory.sol";
import "../../src/wallet/KintoWallet.sol";
import "../../src/sample/Counter.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import {ERC20Multisender} from "@kinto-core-script/utils/ERC20MultiSender.sol";
import {stdJson} from "forge-std/StdJson.sol";

contract Script is MigrationHelper {
    using stdJson for string;

    address internal constant EIGEN = 0xe16E00eeFCd866e8aE5a4e43bBdd6831da6391E1;

    function run() public override {
        super.run();

        string memory json = vm.readFile("./script/data/EIGEN_finalv2_distribution.json");
        string[] memory keys = vm.parseJsonKeys(json, "$");
        address[] memory users = new address[](keys.length);
        uint256[] memory amounts = new uint256[](keys.length);
        for (uint256 index = 0; index < keys.length; index++) {
            uint256 amount = json.readUint(string.concat(".", keys[index]));
            address user = vm.parseAddress(keys[index]);
            users[index] = user;
            amounts[index] = amount;
        }
        uint256 batchSize = 100;
        uint256 totalBatches = (keys.length + batchSize - 1) / batchSize;

        uint256 balance0 = IERC20(EIGEN).balanceOf(0x68242cfeDA40Ff286b045D388f4c5859713027AE);
        uint256 balance1 = IERC20(EIGEN).balanceOf(0x8c962d232219Ba491F2099F03E43E29E2CAb7bEA);
        uint256 balance2 = IERC20(EIGEN).balanceOf(0xa4aC7205D57194547b18021127ceF8DEcF076387);
        uint256 balance3 = IERC20(EIGEN).balanceOf(0x5A68fa975f400679b88F8b43c4a8A0580E7F9cd9);
        uint256 balance4 = IERC20(EIGEN).balanceOf(0x43Def40c4AF010961FE9B4a5eA233C7D8b6aa1FD);

        bytes memory selectorAndParams = abi.encodeWithSelector(
            IERC20.approve.selector, address(_getChainDeployment("ERC20Multisender")), type(uint256).max
        );
        _handleOps(selectorAndParams, EIGEN);

        for (uint256 batchIndex = 0; batchIndex < totalBatches; batchIndex++) {
            uint256 start = batchIndex * batchSize;
            uint256 end = start + batchSize;
            if (end > keys.length) {
                end = keys.length;
            }

            address[] memory batchUsers = new address[](end - start);
            uint256[] memory batchAmounts = new uint256[](end - start);

            for (uint256 i = start; i < end; i++) {
                batchUsers[i - start] = users[i];
                batchAmounts[i - start] = amounts[i];
            }

            selectorAndParams =
                abi.encodeWithSelector(ERC20Multisender.multisendToken.selector, EIGEN, batchUsers, batchAmounts);
            _handleOps(selectorAndParams, _getChainDeployment("ERC20Multisender"));
        }

        assertEq(IERC20(EIGEN).balanceOf(0x68242cfeDA40Ff286b045D388f4c5859713027AE) - balance0, 4204373759065820160000);
        assertEq(IERC20(EIGEN).balanceOf(0x8c962d232219Ba491F2099F03E43E29E2CAb7bEA) - balance1, 4485924644524230000);
        assertEq(IERC20(EIGEN).balanceOf(0xa4aC7205D57194547b18021127ceF8DEcF076387) - balance2, 1727888335103500000);
        assertEq(IERC20(EIGEN).balanceOf(0x5A68fa975f400679b88F8b43c4a8A0580E7F9cd9) - balance3, 200205000);
        assertEq(IERC20(EIGEN).balanceOf(0x43Def40c4AF010961FE9B4a5eA233C7D8b6aa1FD) - balance4, 3814483158966070000);
    }
}
