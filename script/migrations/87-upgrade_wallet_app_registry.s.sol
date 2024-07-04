// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../../src/apps/KintoAppRegistry.sol";
import "../../src/wallet/KintoWallet.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";

contract KintoMigration87DeployScript is MigrationHelper {
    function run() public override {
        super.run();

        bytes memory bytecode;

        bytecode = abi.encodePacked(
            type(KintoWallet).creationCode,
            abi.encode(
                _getChainDeployment("EntryPoint"),
                _getChainDeployment("KintoID"),
                _getChainDeployment("KintoAppRegistry")
            )
        );
        _deployImplementationAndUpgrade("KintoWallet", "V24", bytecode);

        bytecode = abi.encodePacked(
            type(KintoAppRegistryV7).creationCode, abi.encode(_getChainDeployment("KintoWalletFactory"))
        );
        address impl = _deployImplementationAndUpgrade("KintoAppRegistry", "V7", bytecode);

        // Cleanup tokens
        KintoAppRegistryV7 kintoAppRegistry = KintoAppRegistryV7(payable(impl));
        kintoAppRegistry.overrideChildToParentContract(_getChainDeployment("DAI"), address(0));
        kintoAppRegistry.overrideChildToParentContract(_getChainDeployment("wstETH"), address(0));
        kintoAppRegistry.overrideChildToParentContract(_getChainDeployment("WETH"), address(0));
        kintoAppRegistry.overrideChildToParentContract(_getChainDeployment("USDC"), address(0));
        kintoAppRegistry.overrideChildToParentContract(_getChainDeployment("ENA"), address(0));
        kintoAppRegistry.overrideChildToParentContract(_getChainDeployment("USDe"), address(0));
        kintoAppRegistry.overrideChildToParentContract(_getChainDeployment("EIGEN"), address(0));
        kintoAppRegistry.overrideChildToParentContract(_getChainDeployment("eETH"), address(0));
        kintoAppRegistry.overrideChildToParentContract(_getChainDeployment("sDAI"), address(0));
        kintoAppRegistry.overrideChildToParentContract(_getChainDeployment("sUSDe"), address(0));
        kintoAppRegistry.overrideChildToParentContract(_getChainDeployment("wUSDM"), address(0));
        kintoAppRegistry.overrideChildToParentContract(_getChainDeployment("weETH"), address(0));
        kintoAppRegistry.overrideChildToParentContract(_getChainDeployment("ETHFI"), address(0));
        kintoAppRegistry.overrideChildToParentContract(_getChainDeployment("SolvBTC"), address(0));
        assertEq(kintoAppRegistry.childToParentContract(_getChainDeployment("USDC")), address(0));
        // setup socket sponsored tokens
        address[] memory tokens = new address[](15);
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

        // create bool flag array
        bool[] memory flags = new bool[](15);
        for (uint256 i = 0; i < 15; i++) {
            flags[i] = true;
        }

        // Socket sponsored contracts
        kintoAppRegistry.setSponsoredContracts(0x3e9727470C66B1e77034590926CDe0242B5A3dCc, tokens, flags);
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
        // Dinari prod sponsored contracts
        address[] memory dinariTokens = new address[](1);
        dinariTokens[0] = _getChainDeployment("USDC");
        bool[] memory dinariFlags = new bool[](1);
        dinariFlags[0] = true;
        kintoAppRegistry.setSponsoredContracts(0xB2eEc63Cdc175d6d07B8f69804C0Ab5F66aCC3cb, tokens, flags);
        assertEq(
            kintoAppRegistry.isSponsored(0xB2eEc63Cdc175d6d07B8f69804C0Ab5F66aCC3cb, _getChainDeployment("USDC")), true
        );

        // Dinari stage mock usdc
        dinariTokens[0] = 0x90AB5E52Dfcce749CA062f4e04292fd8a67E86b3;
        kintoAppRegistry.setSponsoredContracts(0xF34f9C994E28254334C83AcE353d814E5fB90815, tokens, flags);
        assertEq(
            kintoAppRegistry.isSponsored(
                0xF34f9C994E28254334C83AcE353d814E5fB90815, 0x90AB5E52Dfcce749CA062f4e04292fd8a67E86b3
            ),
            true
        );
    }
}
