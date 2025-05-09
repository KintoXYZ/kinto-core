// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {MorphoViewer} from "@kinto-core/access/workflows/MorphoViewer.sol";
import {UUPSProxy} from "@kinto-core-test/helpers/UUPSProxy.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

/**
 * @title DeployMorphoViewerScript
 * @notice Deploys a MorphoViewer contract with a vanity address
 * @dev Uses salt to generate a vanity address starting with the specified pattern
 */
contract DeployMorphoViewerScript is Script, MigrationHelper {
    MorphoViewer internal morphoViewer;

    function run() public override {
        super.run();

        address viewerAddr = _getChainDeployment("MorphoViewer");
        if (viewerAddr != address(0)) {
            console2.log("MorphoViewer is already deployed:", viewerAddr);
            return;
        }

        // Deploy the implementation contract
        vm.broadcast(deployerPrivateKey);
        MorphoViewer morphoViewerImpl = new MorphoViewer();

        console2.log("MorphoViewer implementation deployed at:", address(morphoViewerImpl));

        // Calculate the initCodeHash for the proxy contract
        bytes32 initCodeHash =
            keccak256(abi.encodePacked(type(UUPSProxy).creationCode, abi.encode(address(morphoViewerImpl), "")));

        // Mine a salt that produces a vanity address
        (bytes32 salt, address expectedAddress) = mineSalt(initCodeHash, "110940");
        console2.log("Expected proxy address:", expectedAddress);

        // Deploy the proxy contract using the mined salt
        vm.broadcast(deployerPrivateKey);
        UUPSProxy proxy = new UUPSProxy{salt: salt}(address(morphoViewerImpl), "");

        require(address(proxy) == expectedAddress, "Deployed address doesn't match expected address");

        // Initialize the proxy
        vm.broadcast(deployerPrivateKey);
        MorphoViewer(address(proxy)).initialize();

        morphoViewer = MorphoViewer(address(proxy));
        console2.log("MorphoViewer proxy deployed and initialized at:", address(morphoViewer));

        // Save the contract addresses to storage
        saveContractAddress("MorphoViewer-impl", address(morphoViewerImpl));
        saveContractAddress("MorphoViewer", address(morphoViewer));

        console2.log("Deployment complete!");
    }
}
