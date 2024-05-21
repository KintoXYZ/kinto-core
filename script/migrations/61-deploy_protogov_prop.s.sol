// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../../src/tokens/EngenCredits.sol";
import "../../src/governance/EngenGovernance.sol";
import "@openzeppelin/contracts/governance/Governor.sol";

import "@kinto-core-script/utils/MigrationHelper.sol";

contract KintoMigration61DeployScript is MigrationHelper {
    using ECDSAUpgradeable for bytes32;

    function run() public override {
        super.run();
        console.log("Executing with address", msg.sender, vm.envAddress("LEDGER_ADMIN"));

        EngenCredits credits = EngenCredits(_getChainDeployment("EngenCredits"));
        EngenGovernance governance = EngenGovernance(payable(_getChainDeployment("EngenGovernance")));
        credits.mint(vm.envAddress("KintoWallet-admin"), 5e23);

        address[] memory targets = new address[](1);
        targets[0] = address(_getChainDeployment("Counter"));
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeWithSignature("increment()");
        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        bytes memory selectorAndParams = abi.encodeWithSelector(
            Governor.propose.selector, targets, values, data, "ENIP:1 - Kinto Constitution"
        );
        _handleOps(selectorAndParams, address(governance), deployerPrivateKey);

        selectorAndParams =
            abi.encodeWithSelector(Governor.propose.selector, targets, values, data, "ENIP:2 - The Kinto Token");
        _handleOps(selectorAndParams, address(governance), deployerPrivateKey);

        selectorAndParams = abi.encodeWithSelector(
            Governor.propose.selector, targets, values, data, "ENIP:3 - The Mining Program"
        );
        _handleOps(selectorAndParams, address(governance), deployerPrivateKey);
    }
}
