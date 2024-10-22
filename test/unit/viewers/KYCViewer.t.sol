// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@kinto-core/wallet/KintoWallet.sol";
import "@kinto-core/wallet/KintoWalletFactory.sol";
import "@kinto-core/KintoID.sol";
import "@kinto-core/viewers/KYCViewer.sol";

import "@kinto-core-test/SharedSetup.t.sol";
import "@kinto-core-test/helpers/UUPSProxy.sol";

contract KYCViewerUpgraded is KYCViewer {
    function newFunction() external pure returns (uint256) {
        return 1;
    }

    constructor(address _kintoWalletFactory, address _faucet, address _engenCredits, address _kintoAppRegistry)
        KYCViewer(_kintoWalletFactory, _faucet, _engenCredits, _kintoAppRegistry)
    {}
}

contract KYCViewerTest is SharedSetup {
    function testUp() public override {
        super.testUp();
        assertEq(_kycViewer.owner(), _owner);
        assertEq(address(_entryPoint.walletFactory()), address(_kycViewer.walletFactory()));
        assertEq(address(_walletFactory.kintoID()), address(_kycViewer.kintoID()));
        assertEq(address(_engenCredits), address(_kycViewer.engenCredits()));
    }

    /* ============ Upgrade tests ============ */

    function testUpgradeTo() public {
        KYCViewerUpgraded _implementationV2 = new KYCViewerUpgraded(
            address(_walletFactory), address(_faucet), address(_engenCredits), address(_kintoAppRegistry)
        );
        vm.prank(_owner);
        _kycViewer.upgradeTo(address(_implementationV2));
        assertEq(KYCViewerUpgraded(address(_kycViewer)).newFunction(), 1);
    }

    function testUpgradeTo_RevertWhen_CallerIsNotOwner(address someone) public {
        vm.assume(someone != _owner);
        KYCViewerUpgraded _implementationV2 = new KYCViewerUpgraded(
            address(_walletFactory), address(_faucet), address(_engenCredits), address(_kintoAppRegistry)
        );
        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(someone);
        _kycViewer.upgradeTo(address(_implementationV2));
    }

    /* ============ Viewer tests ============ */

    function testIsKYC_WhenBothOwnerAndWallet() public view {
        assertEq(_kycViewer.isKYC(address(_kintoWallet)), _kycViewer.isKYC(_owner));
        assertEq(_kycViewer.isIndividual(address(_kintoWallet)), _kycViewer.isIndividual(_owner));
        assertEq(_kycViewer.isCompany(address(_kintoWallet)), false);
        assertEq(_kycViewer.hasTrait(address(_kintoWallet), 6), false);
        assertEq(_kycViewer.isSanctionsSafe(address(_kintoWallet)), true);
        assertEq(_kycViewer.isSanctionsSafeIn(address(_kintoWallet), 1), true);
    }

    function testHasTraits() public {
        // Set up some traits for the owner
        uint16[] memory traitsToSet = new uint16[](3);
        traitsToSet[0] = 1;
        traitsToSet[1] = 3;
        traitsToSet[2] = 5;
        for (uint16 i = 0; i < traitsToSet.length; i++) {
            vm.prank(_owner);
            _kintoID.addTrait(_owner, traitsToSet[i]);
        }
        // Create an array of trait IDs to check
        uint16[] memory traitsToCheck = new uint16[](5);
        traitsToCheck[0] = 1; // Should be true
        traitsToCheck[1] = 2; // Should be false
        traitsToCheck[2] = 3; // Should be true
        traitsToCheck[3] = 4; // Should be false
        traitsToCheck[4] = 5; // Should be true
        // Call hasTraits function
        bool[] memory results = _kycViewer.hasTraits(_owner, traitsToCheck);
        // Assert the results
        assertEq(results.length, 5);
        assertEq(results[0], true);
        assertEq(results[1], false);
        assertEq(results[2], true);
        assertEq(results[3], false);
        assertEq(results[4], true);
        // Test with wallet address
        bool[] memory resultsWithWallet = _kycViewer.hasTraits(address(_kintoWallet), traitsToCheck);
        // Assert the results are the same when using the wallet address
        for (uint16 i = 0; i < results.length; i++) {
            assertEq(results[i], resultsWithWallet[i]);
        }
    }

    function testGetCountry() public {
        // Set a country trait for the owner (USA with code 840)
        vm.prank(_owner);
        _kintoID.addTrait(_owner, 840);

        // Get the country code
        uint16 countryCode = _kycViewer.getCountry(_owner);

        // Assert the country code
        assertEq(countryCode, 840, "Country code should be 840 (USA)");

        // Test with an address that has no country trait set
        address noCountryAddress = address(0x123);
        uint16 noCountry = _kycViewer.getCountry(noCountryAddress);
        assertEq(noCountry, 0, "Address with no country should return 0");
    }

    function testGetUserInfoWithCredits() public {
        address[] memory _wallets = new address[](1);
        uint256[] memory _points = new uint256[](1);
        _wallets[0] = address(_kintoWallet);
        _points[0] = 5e18;
        vm.prank(_owner);
        _engenCredits.setCredits(_wallets, _points);

        IKYCViewer.UserInfo memory userInfo = _kycViewer.getUserInfo(_owner, payable(address(_kintoWallet)));
        // verify properties
        assertEq(userInfo.ownerBalance, _owner.balance);
        assertEq(userInfo.walletBalance, address(_kintoWallet).balance);
        assertEq(userInfo.walletPolicy, _kintoWallet.signerPolicy());
        assertEq(userInfo.walletOwners.length, 1);
        assertEq(userInfo.claimedFaucet, true);
        assertEq(userInfo.engenCreditsEarned, 5e18);
        assertEq(userInfo.engenCreditsClaimed, 0);
        assertEq(userInfo.hasNFT, true);
        assertEq(userInfo.isKYC, _kycViewer.isKYC(_owner));

        vm.prank(address(_kintoWallet));
        _engenCredits.mintCredits();
        userInfo = _kycViewer.getUserInfo(_owner, payable(address(_kintoWallet)));
        assertEq(userInfo.engenCreditsClaimed, 5e18);
    }

    function testGetUserInfo_WhenWalletDoesNotExist() public view {
        IKYCViewer.UserInfo memory userInfo = _kycViewer.getUserInfo(_owner, payable(address(123)));

        // verify properties
        assertEq(userInfo.ownerBalance, _owner.balance);
        assertEq(userInfo.walletBalance, 0);
        assertEq(userInfo.walletPolicy, 0);
        assertEq(userInfo.recoveryTs, 0);
        assertEq(userInfo.walletOwners.length, 0);
        assertEq(userInfo.engenCreditsEarned, 0);
        assertEq(userInfo.engenCreditsClaimed, 0);
        assertEq(userInfo.claimedFaucet, true);
        assertEq(userInfo.hasNFT, true);
        assertEq(userInfo.isKYC, _kycViewer.isKYC(_owner));
    }

    function testGetUserInfo_WhenAccountDoesNotExist() public view {
        IKYCViewer.UserInfo memory userInfo = _kycViewer.getUserInfo(address(111), payable(address(123)));

        // verify properties
        assertEq(userInfo.ownerBalance, 0);
        assertEq(userInfo.walletBalance, 0);
        assertEq(userInfo.walletPolicy, 0);
        assertEq(userInfo.recoveryTs, 0);
        assertEq(userInfo.walletOwners.length, 0);
        assertEq(userInfo.claimedFaucet, false);
        assertEq(userInfo.engenCreditsEarned, 0);
        assertEq(userInfo.engenCreditsClaimed, 0);
        assertEq(userInfo.hasNFT, false);
        assertEq(userInfo.isKYC, _kycViewer.isKYC(address(111)));
    }
}
