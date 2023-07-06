// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/KintoID.sol";
import "../src/interfaces/IKintoID.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";
import { SignatureChecker } from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "forge-std/console.sol";

contract UUPSProxy is ERC1967Proxy {
    constructor(address _implementation, bytes memory _data)
        ERC1967Proxy(_implementation, _data)
    {}
}

contract KintoInitialDeployScript is Script {

    using ECDSAUpgradeable for bytes32;
    using SignatureChecker for address;

    KintoID _implementation;
    KintoID _kintoIDv1;
    UUPSProxy _proxy;

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        _implementation = new KintoID();
        // deploy proxy contract and point it to implementation
        _proxy = new UUPSProxy(address(_implementation), "");
        // wrap in ABI to support easier calls
        _kintoIDv1 = KintoID(address(_proxy));
        // Initialize proxy
        _kintoIDv1.initialize();
        vm.stopBroadcast();
    }
}

contract KintoIDV2 is KintoID {
  constructor() KintoID() {}
}

contract KintoUpgradeScript is Script {

    using ECDSAUpgradeable for bytes32;
    using SignatureChecker for address;

    KintoID _implementation;
    KintoID _oldKinto;

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        console.log('address proxy', vm.envAddress("ID_PROXY_ADDRESS"));
        _oldKinto = KintoID(payable(vm.envAddress("ID_PROXY_ADDRESS")));
        console.log(_oldKinto.name());
        console.log('deploying new implementation');
        KintoIDV2 implementationV2 = new KintoIDV2();
        console.log('before upgrade');
        _oldKinto.upgradeTo(address(implementationV2));
        // re-wrap the proxy
        console.log('upgraded');
        vm.stopBroadcast();
    }

}
