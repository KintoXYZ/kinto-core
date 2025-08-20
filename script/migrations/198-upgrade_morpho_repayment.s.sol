// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {console2} from "forge-std/console2.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import {MorphoRepayment} from "@kinto-core/vaults/MorphoRepayment.sol";
import {
    IERC20Upgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";

contract UpgradeMorphoRepayment is MigrationHelper {

    address public constant K = 0x010700808D59d2bb92257fCafACfe8e5bFF7aB87;
    address public constant USDC = 0x05DC0010C9902EcF6CBc921c6A4bd971c69E5A2E;

    function run() public override {
        super.run();


        MorphoRepayment morphoRepayment = MorphoRepayment(payable(_getChainDeployment("MorphoRepayment")));
        if (address(morphoRepayment) == address(0)) {
            console2.log("MorphoRepayment has to be deployed");
            return;
        }

        vm.broadcast(deployerPrivateKey);
        MorphoRepayment newImpl = new MorphoRepayment(IERC20Upgradeable(K), IERC20Upgradeable(USDC));

        bytes memory bytecode = abi.encodePacked(type(MorphoRepayment).creationCode);

        _upgradeTo(address(morphoRepayment), address(newImpl), deployerPrivateKey);

        console2.log('New impl V4', address(newImpl));
    }
}
