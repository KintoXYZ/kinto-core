// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "src/KintoID.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract UUPSProxy is ERC1967Proxy {
    constructor(address _implementation, bytes memory _data)
        ERC1967Proxy(_implementation, _data)
    {}
}

contract KintoIDV2 is KintoID {
  constructor() KintoID() {}

  //
  function newFunction() public pure returns (uint256) {
      return 1;
  }
}

contract KintoIDTest is Test {

    KintoID implementation;

    KintoID kintoIDv1;
    KintoIDV2 kintoIDv2;
    UUPSProxy proxy;

    address owner = address(1);
    address signer = address(2);
    address user = address(3);
    address user2 = address(4);
    address upgrader = address(5);

    function setUp() public {
        vm.startPrank(owner);
        vm.deal(address(owner), 1e18);
        implementation = new KintoID();
        // deploy proxy contract and point it to implementation
        proxy = new UUPSProxy(address(implementation), "");
        // wrap in ABI to support easier calls
        kintoIDv1 = KintoID(address(proxy));
        // Initialize proxy
        kintoIDv1.initialize();
        vm.stopPrank();
    }

    function testUp() public {
        assertEq(kintoIDv1.lastMonitoredAt(), block.timestamp);
        assertEq(kintoIDv1.name(), "Kinto ID");
        assertEq(kintoIDv1.symbol(), "KINID");
        assertEq(kintoIDv1.KYC_TOKEN_ID(), 1);
    }

    function testOwnerCanUpgrade() public {
        vm.startPrank(owner);
        KintoIDV2 implementationV2 = new KintoIDV2();
        kintoIDv1.upgradeTo(address(implementationV2));
        // re-wrap the proxy
        kintoIDv2 = KintoIDV2(address(proxy));
        assertEq(kintoIDv2.newFunction(), 1);
        vm.stopPrank();
    }

    function testFailOthersCannotUpgrade() public {
        KintoIDV2 implementationV2 = new KintoIDV2();
        kintoIDv1.upgradeTo(address(implementationV2));
        // re-wrap the proxy
        kintoIDv2 = KintoIDV2(address(proxy));
        assertEq(kintoIDv2.newFunction(), 1);
    }

    function testAuthorizedCanUpgrade() public {
        assertEq(false, kintoIDv1.hasRole(kintoIDv1.UPGRADER_ROLE(), upgrader));
        vm.startPrank(owner);
        kintoIDv1.grantRole(kintoIDv1.UPGRADER_ROLE(), upgrader);
        vm.stopPrank();
        vm.startPrank(upgrader);
        // Upgrade from the upgrader account
        assertEq(true, kintoIDv1.hasRole(kintoIDv1.UPGRADER_ROLE(), upgrader));
        KintoIDV2 implementationV2 = new KintoIDV2();
        kintoIDv1.upgradeTo(address(implementationV2));
        // re-wrap the proxy
        kintoIDv2 = KintoIDV2(address(proxy));
        assertEq(kintoIDv2.newFunction(), 1);
        vm.stopPrank();
    }

}
