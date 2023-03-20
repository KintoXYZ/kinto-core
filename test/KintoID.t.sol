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
        kintoIDv1.grantRole(kintoIDv1.KYC_PROVIDER_ROLE(), kyc_provider);
        vm.stopPrank();
    }

    function testUp() public {
        assertEq(kintoIDv1.lastMonitoredAt(), block.timestamp);
        assertEq(kintoIDv1.name(), "Kinto ID");
        assertEq(kintoIDv1.symbol(), "KINID");
        assertEq(kintoIDv1.KYC_TOKEN_ID(), 1);
    }

    // Upgrade Tests

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

    // Mint Tests

    function testMintIndividualKYC() public {
        IKintoID.SignatureData memory sigdata = auxCreateSignature(user, user, 3, block.timestamp + 1000);
        uint8[] memory traits = new uint8[](1);
        traits[0] = 1;
        vm.startPrank(kyc_provider);
        assertEq(kintoIDv1.isKYC(user), false);
        kintoIDv1.mintIndividualKyc(sigdata, traits);
        assertEq(kintoIDv1.isKYC(user), true);
        assertEq(kintoIDv1.isIndividual(user), true);
        assertEq(kintoIDv1.mintedAt(user), block.timestamp);
        assertEq(kintoIDv1.hasTrait(user, 1), true);
        assertEq(kintoIDv1.hasTrait(user, 2), false);
        assertEq(kintoIDv1.balanceOf(user, kintoIDv1.KYC_TOKEN_ID()), 1);
    }

    function testMintCompanyKYC() public {
        IKintoID.SignatureData memory sigdata = auxCreateSignature(user, user, 3, block.timestamp + 1000);
        uint8[] memory traits = new uint8[](1);
        traits[0] = 2;
        vm.startPrank(kyc_provider);
        kintoIDv1.mintCompanyKyc(sigdata, traits);
        assertEq(kintoIDv1.isKYC(user), true);
        assertEq(kintoIDv1.isCompany(user), true);
        assertEq(kintoIDv1.mintedAt(user), block.timestamp);
        assertEq(kintoIDv1.hasTrait(user, 1), false);
        assertEq(kintoIDv1.hasTrait(user, 2), true);
        assertEq(kintoIDv1.balanceOf(user, kintoIDv1.KYC_TOKEN_ID()), 1);
    }

    function testMintIndividualKYCWithInvalidSender() public {
        IKintoID.SignatureData memory sigdata = auxCreateSignature(user, user, 3, block.timestamp + 1000);
        uint8[] memory traits = new uint8[](1);
        traits[0] = 1;
        vm.startPrank(user);
        vm.expectRevert("Invalid Provider");
        kintoIDv1.mintIndividualKyc(sigdata, traits);
    }

    function testMintIndividualKYCWithInvalidSigner() public {
        IKintoID.SignatureData memory sigdata = auxCreateSignature(user, user, 5, block.timestamp + 1000);
        uint8[] memory traits = new uint8[](1);
        traits[0] = 1;
        vm.startPrank(kyc_provider);
        vm.expectRevert("Invalid Signer");
        kintoIDv1.mintIndividualKyc(sigdata, traits);
    }

    function testMintIndividualKYCWithInvalidNonce() public {
        IKintoID.SignatureData memory sigdata = auxCreateSignature(user, user, 3, block.timestamp + 1000);
        uint8[] memory traits = new uint8[](1);
        traits[0] = 1;
        vm.startPrank(kyc_provider);
        kintoIDv1.mintIndividualKyc(sigdata, traits);
        vm.expectRevert("Invalid Nonce");
        kintoIDv1.mintIndividualKyc(sigdata, traits);
    }

    function testMintIndividualKYCWithExpiredSignature() public {
        IKintoID.SignatureData memory sigdata = auxCreateSignature(user, user, 3, block.timestamp - 1000);
        uint8[] memory traits = new uint8[](1);
        traits[0] = 1;
        vm.startPrank(kyc_provider);
        vm.expectRevert("Signature has expired");
        kintoIDv1.mintIndividualKyc(sigdata, traits);
    }

    // Burn Tests

    function testBurnKYC() public {
        IKintoID.SignatureData memory sigdata = auxCreateSignature(user, user, 3, block.timestamp + 1000);
        uint8[] memory traits = new uint8[](1);
        traits[0] = 1;
        vm.startPrank(kyc_provider);
        kintoIDv1.mintIndividualKyc(sigdata, traits);
        assertEq(kintoIDv1.isKYC(user), true);
        sigdata = auxCreateSignature(user, user, 3, block.timestamp + 1000);
        kintoIDv1.burnKYC(sigdata);
        assertEq(kintoIDv1.balanceOf(user, kintoIDv1.KYC_TOKEN_ID()), 0);
    }

    function testOnlyProviderCanBurnKYC() public {
        IKintoID.SignatureData memory sigdata = auxCreateSignature(user, user, 3, block.timestamp + 1000);
        uint8[] memory traits = new uint8[](1);
        traits[0] = 1;
        vm.startPrank(kyc_provider);
        kintoIDv1.mintIndividualKyc(sigdata, traits);
        assertEq(kintoIDv1.isKYC(user), true);
        sigdata = auxCreateSignature(user, user, 3, block.timestamp + 1000);
        vm.stopPrank();
        vm.startPrank(user);
        vm.expectRevert("Invalid Provider");
        kintoIDv1.burnKYC(sigdata);}

    function testBurnFailsWithoutMinting() public {
        IKintoID.SignatureData memory sigdata = auxCreateSignature(user, user, 3, block.timestamp + 1000);
        vm.startPrank(kyc_provider);
        vm.expectRevert("Nothing to burn");
        kintoIDv1.burnKYC(sigdata);
    }

    function testBurningTwiceFails() public {
        IKintoID.SignatureData memory sigdata = auxCreateSignature(user, user, 3, block.timestamp + 1000);
        uint8[] memory traits = new uint8[](1);
        traits[0] = 1;
        vm.startPrank(kyc_provider);
        kintoIDv1.mintIndividualKyc(sigdata, traits);
        assertEq(kintoIDv1.isKYC(user), true);
        sigdata = auxCreateSignature(user, user, 3, block.timestamp + 1000);
        kintoIDv1.burnKYC(sigdata);
        sigdata = auxCreateSignature(user, user, 3, block.timestamp + 1000);
        vm.expectRevert("Nothing to burn");
        kintoIDv1.burnKYC(sigdata);
    }

    // Monitor Tests
    function testMonitor() public {
        vm.startPrank(kyc_provider);
        kintoIDv1.monitor();
        assertEq(kintoIDv1.lastMonitoredAt(), block.timestamp);
    }

    function testFailOnlyProviderCanMonitor() public {
        vm.startPrank(user);
        kintoIDv1.monitor();
    }

    function testIsSanctionsMonitored() public {
        vm.startPrank(kyc_provider);
        kintoIDv1.monitor();
        assertEq(kintoIDv1.isSanctionsMonitored(1), true);
        vm.warp(block.timestamp + 7 days);
        assertEq(kintoIDv1.isSanctionsMonitored(8), true);
        assertEq(kintoIDv1.isSanctionsMonitored(6), false);
    }

    // Trait Tests
    function testProviderCanAddTrait() public {
        vm.startPrank(kyc_provider);
        kintoIDv1.addTrait(user, 1);
        assertEq(kintoIDv1.hasTrait(user,1), true);
    }

    function testFailUserCannotAddTrait() public {
        vm.startPrank(user);
        kintoIDv1.addTrait(user, 1);
    }

    function testProviderCanRemoveTrait() public {
        vm.startPrank(kyc_provider);
        kintoIDv1.addTrait(user, 1);
        assertEq(kintoIDv1.hasTrait(user,1), true);
        kintoIDv1.removeTrait(user, 1);
        assertEq(kintoIDv1.hasTrait(user,1), false);
    }

    function testFailUserCannotRemoveTrait() public {
        vm.startPrank(kyc_provider);
        kintoIDv1.addTrait(user, 1);
        assertEq(kintoIDv1.hasTrait(user,1), true);
        vm.stopPrank();
        vm.startPrank(user);
        kintoIDv1.removeTrait(user, 1);
    }

    // Sanction Tests
    function testProviderCanAddSanction() public {
        vm.startPrank(kyc_provider);
        kintoIDv1.addSanction(user, 1);
        assertEq(kintoIDv1.isSanctionsSafeIn(user,1), false);
        assertEq(kintoIDv1.isSanctionsSafe(user), false);
    }

    function testProviderCanRemoveSancion() public {
        vm.startPrank(kyc_provider);
        kintoIDv1.addSanction(user, 1);
        assertEq(kintoIDv1.isSanctionsSafeIn(user,1), false);
        kintoIDv1.removeSanction(user, 1);
        assertEq(kintoIDv1.isSanctionsSafeIn(user,1), true);
        assertEq(kintoIDv1.isSanctionsSafe(user), true);
    }

    function testFailUserCannotAddSanction() public {
        vm.startPrank(user);
        kintoIDv1.addSanction(user2, 1);
    }

    function testFailUserCannotRemoveSanction() public {
        vm.startPrank(kyc_provider);
        kintoIDv1.addSanction(user, 1);
        assertEq(kintoIDv1.isSanctionsSafeIn(user,1), false);
        vm.stopPrank();
        vm.startPrank(user);
        kintoIDv1.removeSanction(user2, 1);
    }

    // Transfer

    function testFailTransfersAreDisabled() public {
        IKintoID.SignatureData memory sigdata = auxCreateSignature(user, user, 3, block.timestamp + 1000);
        uint8[] memory traits = new uint8[](1);
        traits[0] = 1;
        vm.startPrank(kyc_provider);
        assertEq(kintoIDv1.isKYC(user), false);
        kintoIDv1.mintIndividualKyc(sigdata, traits);
        vm.stopPrank();
        vm.startPrank(user);
        kintoIDv1.safeTransferFrom(user, user2, kintoIDv1.KYC_TOKEN_ID(), 1, "0x0");
        assertEq(kintoIDv1.balanceOf(user, kintoIDv1.KYC_TOKEN_ID()), 0);
        assertEq(kintoIDv1.balanceOf(user2, kintoIDv1.KYC_TOKEN_ID()), 1);

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
