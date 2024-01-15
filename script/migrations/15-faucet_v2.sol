// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "../../src/Faucet.sol";

import "../../test/helpers/Create2Helper.sol";
import "../../test/helpers/ArtifactsReader.sol";
import "../../test/helpers/UUPSProxy.sol";

import "forge-std/Script.sol";
import "forge-std/console.sol";

contract KintoMigration15DeployScript is Create2Helper, ArtifactsReader {
    using ECDSAUpgradeable for bytes32;

    Faucet _implementation;
    Faucet _faucet;
    UUPSProxy _proxy;

    function setUp() public {}

    function run() public {
        console.log("Chain ID", vm.toString(block.chainid));

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        console.log("Executing with address", msg.sender);

        address faucetAddr = payable(_getChainDeployment("Faucet"));
        if (faucetAddr != address(0)) {
            console.log("Already deployed faucet", faucetAddr);
            return;
        }

        // make sure wallet factory is deployed
        address factory = _getChainDeployment("KintoWalletFactory");
        require(factory != address(0), "Need to deploy the wallet factory first");

        // Faucet
        faucetAddr = computeAddress(0, abi.encodePacked(type(Faucet).creationCode));
        if (isContract(faucetAddr)) {
            _implementation = Faucet(payable(faucetAddr));
            console.log("Already deployed faucet implementation at", address(faucetAddr));
        } else {
            // Deploy Faucet implementation
            vm.broadcast(deployerPrivateKey);
            _implementation = new Faucet{salt: 0}(factory);
            console.log("Faucet implementation deployed at", address(_implementation));
        }
        address faucetProxyAddr =
            computeAddress(0, abi.encodePacked(type(UUPSProxy).creationCode, abi.encode(address(_implementation), "")));
        if (isContract(faucetProxyAddr)) {
            _proxy = UUPSProxy(payable(faucetProxyAddr));
            _faucet = Faucet(payable(address(_proxy)));
            console.log("Already deployed Faucet proxy at", address(faucetProxyAddr));
        } else {
            // deploy proxy contract and point it to implementation
            vm.broadcast(deployerPrivateKey);
            _proxy = new UUPSProxy{salt: 0}(address(_implementation), "");
            console.log("Faucet proxy deployed at ", address(_proxy));

            // initialize proxy
            vm.broadcast(deployerPrivateKey);
            Faucet(payable(address(_proxy))).initialize();
        }

        // Writes the addresses to a file
        console.log(string.concat("Faucet-impl: ", vm.toString(address(_implementation))));
        console.log(string.concat("Faucet: ", vm.toString(address(_proxy))));
    }
}
