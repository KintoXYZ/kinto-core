// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../../src/apps/KintoAppRegistry.sol";
import "../../src/wallet/KintoWallet.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import "forge-std/console2.sol";

contract Script is MigrationHelper {
    function run() public override {
        super.run();

        KintoAppRegistry kintoAppRegistry = KintoAppRegistry(_getChainDeployment("KintoAppRegistry"));

        // setup socket sponsored tokens
        address[] memory tokens = new address[](28);
        tokens[0] = _getChainDeployment("DAI");
        tokens[1] = _getChainDeployment("wstETH");
        tokens[2] = _getChainDeployment("WETH");
        tokens[3] = _getChainDeployment("USDC");
        tokens[4] = _getChainDeployment("ENA");
        tokens[5] = _getChainDeployment("USDe");
        tokens[6] = _getChainDeployment("EIGEN");
        tokens[7] = _getChainDeployment("eETH");
        tokens[8] = _getChainDeployment("sDAI");
        tokens[9] = _getChainDeployment("sUSDe");
        tokens[10] = _getChainDeployment("wUSDM");
        tokens[11] = _getChainDeployment("weETH");
        tokens[12] = _getChainDeployment("ETHFI");
        tokens[13] = _getChainDeployment("SolvBTC");
        tokens[14] = _getChainDeployment("MKR");
        tokens[15] = _getChainDeployment("PAXG");
        tokens[16] = _getChainDeployment("XAUt");
        tokens[17] = _getChainDeployment("stEUR");
        tokens[18] = _getChainDeployment("stUSD");
        tokens[19] = _getChainDeployment("WBTC");
        tokens[20] = _getChainDeployment("USDT");
        tokens[21] = _getChainDeployment("ARB");
        tokens[22] = _getChainDeployment("LINK");
        tokens[23] = _getChainDeployment("GHO");
        tokens[24] = _getChainDeployment("rETH");
        tokens[25] = _getChainDeployment("cbETH");
        tokens[26] = _getChainDeployment("cbBTC");
        tokens[27] = _getChainDeployment("AAVE");

        // create bool flag array
        bool[] memory flags = new bool[](28);
        for (uint256 i = 0; i < flags.length; i++) {
            flags[i] = true;
        }

        _handleOps(
            abi.encodeWithSelector(
                KintoAppRegistry.setSponsoredContracts.selector,
                0x3e9727470C66B1e77034590926CDe0242B5A3dCc,
                tokens,
                flags
            ),
            address(_getChainDeployment("KintoAppRegistry"))
        );

        assertEq(
            kintoAppRegistry.isSponsored(0x3e9727470C66B1e77034590926CDe0242B5A3dCc, _getChainDeployment("DAI")), true
        );
        assertEq(
            kintoAppRegistry.isSponsored(0x3e9727470C66B1e77034590926CDe0242B5A3dCc, _getChainDeployment("wstETH")),
            true
        );
        assertEq(
            kintoAppRegistry.isSponsored(0x3e9727470C66B1e77034590926CDe0242B5A3dCc, _getChainDeployment("WETH")), true
        );
        assertEq(
            kintoAppRegistry.isSponsored(0x3e9727470C66B1e77034590926CDe0242B5A3dCc, _getChainDeployment("USDC")), true
        );
        assertEq(
            kintoAppRegistry.isSponsored(0x3e9727470C66B1e77034590926CDe0242B5A3dCc, _getChainDeployment("ENA")), true
        );
        assertEq(
            kintoAppRegistry.isSponsored(0x3e9727470C66B1e77034590926CDe0242B5A3dCc, _getChainDeployment("USDe")), true
        );
        assertEq(
            kintoAppRegistry.isSponsored(0x3e9727470C66B1e77034590926CDe0242B5A3dCc, _getChainDeployment("EIGEN")), true
        );
        assertEq(
            kintoAppRegistry.isSponsored(0x3e9727470C66B1e77034590926CDe0242B5A3dCc, _getChainDeployment("eETH")), true
        );
        assertEq(
            kintoAppRegistry.isSponsored(0x3e9727470C66B1e77034590926CDe0242B5A3dCc, _getChainDeployment("sDAI")), true
        );
        assertEq(
            kintoAppRegistry.isSponsored(0x3e9727470C66B1e77034590926CDe0242B5A3dCc, _getChainDeployment("sUSDe")), true
        );
        assertEq(
            kintoAppRegistry.isSponsored(0x3e9727470C66B1e77034590926CDe0242B5A3dCc, _getChainDeployment("wUSDM")), true
        );
        assertEq(
            kintoAppRegistry.isSponsored(0x3e9727470C66B1e77034590926CDe0242B5A3dCc, _getChainDeployment("weETH")), true
        );
        assertEq(
            kintoAppRegistry.isSponsored(0x3e9727470C66B1e77034590926CDe0242B5A3dCc, _getChainDeployment("ETHFI")), true
        );
        assertEq(
            kintoAppRegistry.isSponsored(0x3e9727470C66B1e77034590926CDe0242B5A3dCc, _getChainDeployment("SolvBTC")),
            true
        );
        assertEq(
            kintoAppRegistry.isSponsored(0x3e9727470C66B1e77034590926CDe0242B5A3dCc, _getChainDeployment("MKR")), true
        );
        assertEq(
            kintoAppRegistry.isSponsored(0x3e9727470C66B1e77034590926CDe0242B5A3dCc, _getChainDeployment("PAXG")), true
        );
        assertEq(
            kintoAppRegistry.isSponsored(0x3e9727470C66B1e77034590926CDe0242B5A3dCc, _getChainDeployment("XAUt")), true
        );
        assertEq(
            kintoAppRegistry.isSponsored(0x3e9727470C66B1e77034590926CDe0242B5A3dCc, _getChainDeployment("stEUR")), true
        );
        assertEq(
            kintoAppRegistry.isSponsored(0x3e9727470C66B1e77034590926CDe0242B5A3dCc, _getChainDeployment("stUSD")), true
        );
        assertEq(
            kintoAppRegistry.isSponsored(0x3e9727470C66B1e77034590926CDe0242B5A3dCc, _getChainDeployment("WBTC")), true
        );
        assertEq(
            kintoAppRegistry.isSponsored(0x3e9727470C66B1e77034590926CDe0242B5A3dCc, _getChainDeployment("USDT")), true
        );
        assertEq(
            kintoAppRegistry.isSponsored(0x3e9727470C66B1e77034590926CDe0242B5A3dCc, _getChainDeployment("ARB")), true
        );
        assertEq(
            kintoAppRegistry.isSponsored(0x3e9727470C66B1e77034590926CDe0242B5A3dCc, _getChainDeployment("LINK")), true
        );
        assertEq(
            kintoAppRegistry.isSponsored(0x3e9727470C66B1e77034590926CDe0242B5A3dCc, _getChainDeployment("GHO")), true
        );
        assertEq(
            kintoAppRegistry.isSponsored(0x3e9727470C66B1e77034590926CDe0242B5A3dCc, _getChainDeployment("rETH")), true
        );
        assertEq(
            kintoAppRegistry.isSponsored(0x3e9727470C66B1e77034590926CDe0242B5A3dCc, _getChainDeployment("cbETH")), true
        );
        assertEq(
            kintoAppRegistry.isSponsored(0x3e9727470C66B1e77034590926CDe0242B5A3dCc, _getChainDeployment("cbBTC")), true
        );
        assertEq(
            kintoAppRegistry.isSponsored(0x3e9727470C66B1e77034590926CDe0242B5A3dCc, _getChainDeployment("AAVE")), true
        );
    }
}
