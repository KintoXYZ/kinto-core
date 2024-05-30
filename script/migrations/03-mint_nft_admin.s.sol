// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../../src/KintoID.sol";

import "../../test/helpers/Create2Helper.sol";
import "../../test/helpers/ArtifactsReader.sol";
import "../../test/helpers/SignatureHelper.sol";

import "forge-std/Script.sol";
import "forge-std/console.sol";

contract KintoMigration3DeployScript is Create2Helper, SignatureHelper, ArtifactsReader {
    KintoID _kintoID;

    function setUp() public {}

    function run() public {
        console.log("RUNNING ON CHAIN WITH ID", vm.toString(block.chainid));

        // if not using ledger, replace
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.rememberKey(deployerPrivateKey);

        console.log("Executing with address", deployer);
        address walletFactoryAddr = _getChainDeployment("KintoWalletFactory");
        if (walletFactoryAddr == address(0)) {
            console.log("Need to execute main deploy script first", walletFactoryAddr);
            return;
        }

        // mint an nft to the owner
        _kintoID = KintoID(_getChainDeployment("KintoID"));
        IKintoID.SignatureData memory sigdata =
            _auxCreateSignature(_kintoID, deployer, deployerPrivateKey, block.timestamp + 1000);

        uint16[] memory traits = new uint16[](1);
        traits[0] = 0; // ADMIN

        vm.broadcast();
        _kintoID.mintIndividualKyc(sigdata, traits);
    }
}
