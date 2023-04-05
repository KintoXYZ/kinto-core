// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "src/KintoID.sol";
import "src/interfaces/IKintoID.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
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
    KintoID implementation;

    KintoID kintoIDv1;
    UUPSProxy proxy;

    address owner = address(1);

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        implementation = new KintoID();
        // deploy proxy contract and point it to implementation
        proxy = new UUPSProxy(address(implementation), "");
        // wrap in ABI to support easier calls
        kintoIDv1 = KintoID(address(proxy));
        // Initialize proxy
        kintoIDv1.initialize();
        vm.stopBroadcast();
    }
}

contract KintoIDV2 is KintoID {
  constructor() KintoID() {}
}

contract KintoUpgradeScript is Script {

    using ECDSAUpgradeable for bytes32;
    using SignatureChecker for address;
    KintoID implementation;

    KintoID oldKinto;
    KintoIDV2 newKinto;
    UUPSProxy proxy;

    address owner = address(1);

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        console.log('address proxy', vm.envAddress("ID_PROXY_ADDRESS"));
        oldKinto = KintoID(payable(vm.envAddress("ID_PROXY_ADDRESS")));
        console.log(oldKinto.name());
        console.log('deploying new implementation');
        KintoIDV2 implementationV2 = new KintoIDV2();
        console.log('before upgrade');
        oldKinto.upgradeTo(address(implementationV2));
        // re-wrap the proxy
        console.log('upgraded');
        vm.stopBroadcast();
    }

}
