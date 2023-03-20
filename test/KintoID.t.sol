// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "src/KintoID.sol";
import "src/interfaces/IKintoID.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "forge-std/Test.sol";
import "forge-std/console.sol";

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
    using ECDSAUpgradeable for bytes32;
    using SignatureChecker for address;
    KintoID implementation;

    KintoID kintoIDv1;
    KintoIDV2 kintoIDv2;
    UUPSProxy proxy;

    address owner = address(1);
    address kyc_provider = address(2);
    address user = vm.addr(3);
    address user2 = address(4);
    address upgrader = address(5);

    function setUp() public {
        vm.startPrank(owner);
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
        // Upgrade from the upgrader account
        assertEq(true, kintoIDv1.hasRole(kintoIDv1.UPGRADER_ROLE(), upgrader));
        KintoIDV2 implementationV2 = new KintoIDV2();
        vm.startPrank(upgrader);
        kintoIDv1.upgradeTo(address(implementationV2));
        // re-wrap the proxy
        kintoIDv2 = KintoIDV2(address(proxy));
        vm.stopPrank();
        assertEq(kintoIDv2.newFunction(), 1);
    }

    function testMintIndividualKYC() public {
        vm.startPrank(owner);
        kintoIDv1.grantRole(kintoIDv1.KYC_PROVIDER_ROLE(), kyc_provider);
        vm.stopPrank();
        IKintoID.SignatureData memory sigdata = auxCreateSignature(user, user, 3, block.timestamp + 1000);
        uint8[] memory traits = new uint8[](1);
        traits[0] = 1;
        vm.startPrank(kyc_provider);
        kintoIDv1.mintIndividualKyc(sigdata, traits);
        vm.stopPrank();
        assertEq(kintoIDv1.isKYC(user), true);
        assertEq(kintoIDv1.balanceOf(user, kintoIDv1.KYC_TOKEN_ID()), 1);
    }

    // Create a test for minting a KYC token
    function auxCreateSignature(address _signer, address _account, uint256 _privateKey, uint256 _expiresAt) private view returns (
        IKintoID.SignatureData memory signData
    ) {
        bytes32 hash = keccak256(
            abi.encode(
                _signer,
                address(kintoIDv1),
                _account,
                kintoIDv1.KYC_TOKEN_ID(),
                _expiresAt,
                kintoIDv1.nonces(_signer),
                bytes32(block.chainid)
            )).toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_privateKey, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        return IKintoID.SignatureData(
                _signer,
                _account,
                kintoIDv1.nonces(_signer),
                _expiresAt,
                signature
            );
    }

}
