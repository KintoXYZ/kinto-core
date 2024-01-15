// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "../../src/Faucet.sol";
import "../../src/wallet/KintoWalletFactory.sol";

import "../../test/helpers/Create2Helper.sol";
import "../../test/helpers/ArtifactsReader.sol";
import "../../test/helpers/UUPSProxy.sol";

import "forge-std/Script.sol";
import "forge-std/console.sol";

contract KintoMigration15DeployScript is Create2Helper, ArtifactsReader {
    using ECDSAUpgradeable for bytes32;

    Faucet _implementation;
    UUPSProxy _proxy;

    function setUp() public {}

    function run() public {
        console.log("Chain ID", vm.toString(block.chainid));

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        console.log("Executing with address", msg.sender);

        vm.startBroadcast(deployerPrivateKey);

        // make sure faucet proxy is not already deployed
        address faucetProxy = payable(_getChainDeployment("Faucet"));
        require(faucetProxy == address(0), "Faucet proxy is already deployed");

        // make sure wallet factory is deployed
        address factory = _getChainDeployment("KintoWalletFactory");
        require(factory != address(0), "Need to deploy the wallet factory first");

        // use wallet factory to deploy Faucet implementation & proxy
        KintoWalletFactory walletFactory = KintoWalletFactory(payable(factory));

        // deploy Faucet implementation
        bytes memory bytecode = abi.encodePacked(type(Faucet).creationCode, abi.encode(factory));
        _implementation = Faucet(payable(walletFactory.deployContract(msg.sender, 0, bytecode, bytes32(0))));

        // deploy Faucet proxy
        bytecode = abi.encodePacked(type(UUPSProxy).creationCode, abi.encode(address(_implementation), ""));
        _proxy = UUPSProxy(payable(walletFactory.deployContract(msg.sender, 0, bytecode, bytes32(0))));

        // initialize proxy
        Faucet(payable(address(_proxy))).initialize();

        vm.stopBroadcast();

        // sanity check: faucet has the new claim amount
        require(Faucet(payable(address(_proxy))).CLAIM_AMOUNT() == 1 ether / 2500, "Claim amount is not correct");

        // Writes the addresses to a file
        console.log(string.concat("Faucet-impl: ", vm.toString(address(_implementation))));
        console.log(string.concat("Faucet: ", vm.toString(address(_proxy))));
    }
}
