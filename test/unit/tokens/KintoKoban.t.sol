// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "src/tokens/KintoKoban.sol";
import "@openzeppelin-5.0.1/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// Define the custom errors used in the contracts
error OwnableUnauthorizedAccount(address account);
error UUPSUnauthorizedCall(address caller);

/**
 * @title KintoKobanTest
 * @notice Test suite for the KintoKoban contract using vm.mockCall.
 */
contract KintoKobanTest is Test {
    KintoKoban internal _koban;

    // Addresses of the immutable contracts
    address internal constant WALLET_FACTORY_ADDRESS = 0x8a4720488CA32f1223ccFE5A087e250fE3BC5D75;
    address internal constant KINTO_ID_ADDRESS = 0xf369f78E3A0492CC4e96a90dae0728A38498e9c7;

    // Test accounts
    uint256 internal _ownerPk = 1;
    address internal _owner = vm.addr(_ownerPk);

    uint256 internal _userPk = 2;
    address internal _user = vm.addr(_userPk);

    /**
     * @notice Setup function to initialize the KintoKoban contract.
     */
    function setUp() public {
        // Deploy the implementation contract
        console.log("Deploying implementation contract");
        KintoKoban kobanImplementation = new KintoKoban(1_000_000e18, 10_000e18);

        // Deploy the proxy pointing to the implementation
        vm.startPrank(_owner);
        console.log("Deploying proxy contract");
        ERC1967Proxy proxy = new ERC1967Proxy(address(kobanImplementation), abi.encodeWithSignature("initialize(string,string)", "Kinto Koban", "KBON"));
        console.log("Proxy contract deployed at", address(proxy));
        _koban = KintoKoban(address(proxy));
        console.log("KintoKoban contract deployed at", address(_koban));
        vm.stopPrank();
    }

    /* ============ Initialization Tests ============ */

    /**
     * @notice Test that the contract initializes with correct parameters.
     */
    function testKobanInitialization() public {
        assertEq(_koban.name(), "Kinto Koban");
        assertEq(_koban.symbol(), "KBON");
        assertEq(_koban.owner(), _owner);
        assertEq(_koban.allowMode(), false);

        // Since MAX_SUPPLY_LIMIT and TOTAL_TRANSFER_LIMIT are immutable, access them directly
        assertEq(_koban.MAX_SUPPLY_LIMIT(), 1_000_000e18);
        assertEq(_koban.TOTAL_TRANSFER_LIMIT(), 10_000e18);
    }

    /* ============ Mint Tests ============ */

    /**
     * @notice Test successful minting by the owner.
     */
    function testMint_Success() public {
        vm.startPrank(_owner);
        _koban.mint(_user, 50_000e18);
        assertEq(_koban.balanceOf(_user), 50_000e18);
        assertEq(_koban.totalSupply(), 50_000e18);
        vm.stopPrank();
    }

    /**
     * @notice Test minting that exceeds the maximum supply limit, expecting a revert.
     */
    function testMint_ExceedsMaxSupply_Revert() public {
        vm.startPrank(_owner);
        uint256 attemptedSupply = _koban.totalSupply() + 1_000_001e18;
        vm.expectRevert(abi.encodeWithSelector(KintoKoban.ExceedsMaxSupply.selector, attemptedSupply));
        _koban.mint(_user, 1_000_001e18); // Exceeds MAX_SUPPLY_LIMIT
        vm.stopPrank();
    }

    /**
     * @notice Test that a non-owner cannot mint tokens, expecting a revert.
     */
    function testMint_CallerNotOwner_Revert() public {
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, address(this)));
        _koban.mint(_user, 100e18);
    }

    /* ============ Transfer Tests ============ */

    /**
     * @notice Test a successful token transfer adhering to all restrictions.
     */
    function testTransfer_Success() public {
        address senderWallet = address(0x1001);
        address recipientWallet = address(0x1002);

        // Mock the walletTs to return non-zero timestamps
        uint256 currentTime = block.timestamp;
        vm.mockCall(
            WALLET_FACTORY_ADDRESS,
            abi.encodeWithSelector(IKintoWalletFactory.walletTs.selector, senderWallet),
            abi.encode(currentTime)
        );
        vm.mockCall(
            WALLET_FACTORY_ADDRESS,
            abi.encodeWithSelector(IKintoWalletFactory.walletTs.selector, recipientWallet),
            abi.encode(currentTime)
        );

        // Mock the owners(0) call on sender and recipient wallets
        vm.mockCall(
            senderWallet,
            abi.encodeWithSelector(IKintoWallet.owners.selector, 0),
            abi.encode(_owner)
        );
        vm.mockCall(
            recipientWallet,
            abi.encodeWithSelector(IKintoWallet.owners.selector, 0),
            abi.encode(_user)
        );

        // Mock KYC status
        vm.mockCall(
            KINTO_ID_ADDRESS,
            abi.encodeWithSelector(IKintoID.isKYC.selector, _owner),
            abi.encode(true)
        );
        vm.mockCall(
            KINTO_ID_ADDRESS,
            abi.encodeWithSelector(IKintoID.isKYC.selector, _user),
            abi.encode(true)
        );

        // Mock country traits
        uint16 countryID = 1;
        vm.mockCall(
            KINTO_ID_ADDRESS,
            abi.encodeWithSelector(IKintoID.hasTrait.selector, _owner, countryID),
            abi.encode(true)
        );
        vm.mockCall(
            KINTO_ID_ADDRESS,
            abi.encodeWithSelector(IKintoID.hasTrait.selector, _user, countryID),
            abi.encode(true)
        );

        // Set country list and switch to Allow Mode
        uint16[] memory countries = new uint16[](1);
        countries[0] = countryID;
        vm.prank(_owner);
        _koban.setCountryList(countries);
        vm.prank(_owner);
        _koban.setCountryListMode(true);

        // Mint tokens to senderWallet
        vm.startPrank(_owner);
        _koban.mint(senderWallet, 5_000e18);
        vm.stopPrank();

        // Transfer tokens
        vm.prank(senderWallet);
        bool success = _koban.transfer(recipientWallet, 5_000e18);
        assertTrue(success);
        assertEq(_koban.balanceOf(recipientWallet), 5_000e18);
    }

    /**
     * @notice Test transferring tokens when the transfer amount exceeds TOTAL_TRANSFER_LIMIT, expecting a revert.
     */
    function testTransfer_ExceedsTransferLimit_Revert() public {
        address senderWallet = address(0x1001);
        address recipientWallet = address(0x1002);

        // Mock the walletTs to return non-zero timestamps
        uint256 currentTime = block.timestamp;
        vm.mockCall(
            WALLET_FACTORY_ADDRESS,
            abi.encodeWithSelector(IKintoWalletFactory.walletTs.selector, senderWallet),
            abi.encode(currentTime)
        );
        vm.mockCall(
            WALLET_FACTORY_ADDRESS,
            abi.encodeWithSelector(IKintoWalletFactory.walletTs.selector, recipientWallet),
            abi.encode(currentTime)
        );

        // Mock the owners(0) call on sender and recipient wallets
        vm.mockCall(
            senderWallet,
            abi.encodeWithSelector(IKintoWallet.owners.selector, 0),
            abi.encode(_owner)
        );
        vm.mockCall(
            recipientWallet,
            abi.encodeWithSelector(IKintoWallet.owners.selector, 0),
            abi.encode(_user)
        );

        // Mock KYC status
        vm.mockCall(
            KINTO_ID_ADDRESS,
            abi.encodeWithSelector(IKintoID.isKYC.selector, _owner),
            abi.encode(true)
        );
        vm.mockCall(
            KINTO_ID_ADDRESS,
            abi.encodeWithSelector(IKintoID.isKYC.selector, _user),
            abi.encode(true)
        );

        // Mock country traits
        uint16 countryID = 1;
        vm.mockCall(
            KINTO_ID_ADDRESS,
            abi.encodeWithSelector(IKintoID.hasTrait.selector, _owner, countryID),
            abi.encode(true)
        );
        vm.mockCall(
            KINTO_ID_ADDRESS,
            abi.encodeWithSelector(IKintoID.hasTrait.selector, _user, countryID),
            abi.encode(true)
        );

        // Set country list and switch to Allow Mode
        uint16[] memory countries = new uint16[](1);
        countries[0] = countryID;
        vm.prank(_owner);
        _koban.setCountryList(countries);
        vm.prank(_owner);
        _koban.setCountryListMode(true);

        // Mint tokens to senderWallet
        vm.startPrank(_owner);
        _koban.mint(senderWallet, 20_000e18);
        vm.stopPrank();

        // Attempt to transfer exceeding TOTAL_TRANSFER_LIMIT
        vm.prank(senderWallet);
        vm.expectRevert(abi.encodeWithSelector(KintoKoban.TransferRestricted.selector, uint8(3)));
        _koban.transfer(recipientWallet, 10_001e18);
    }

    /**
     * @notice Test transferring tokens when the recipient is not KYCed, expecting a revert.
     */
    function testTransfer_NotKYCed_Revert() public {
        address senderWallet = address(0x1001);
        address recipientWallet = address(0x1002);

        // Mock the walletTs to return non-zero timestamps
        uint256 currentTime = block.timestamp;
        vm.mockCall(
            WALLET_FACTORY_ADDRESS,
            abi.encodeWithSelector(IKintoWalletFactory.walletTs.selector, senderWallet),
            abi.encode(currentTime)
        );
        vm.mockCall(
            WALLET_FACTORY_ADDRESS,
            abi.encodeWithSelector(IKintoWalletFactory.walletTs.selector, recipientWallet),
            abi.encode(currentTime)
        );

        // Mock the owners(0) call on sender and recipient wallets
        vm.mockCall(
            senderWallet,
            abi.encodeWithSelector(IKintoWallet.owners.selector, 0),
            abi.encode(_owner)
        );
        vm.mockCall(
            recipientWallet,
            abi.encodeWithSelector(IKintoWallet.owners.selector, 0),
            abi.encode(_user)
        );

        // Mock KYC status: Recipient not KYCed
        vm.mockCall(
            KINTO_ID_ADDRESS,
            abi.encodeWithSelector(IKintoID.isKYC.selector, _owner),
            abi.encode(true)
        );
        vm.mockCall(
            KINTO_ID_ADDRESS,
            abi.encodeWithSelector(IKintoID.isKYC.selector, _user),
            abi.encode(false)
        );

        // Mock country traits
        uint16 countryID = 1;
        vm.mockCall(
            KINTO_ID_ADDRESS,
            abi.encodeWithSelector(IKintoID.hasTrait.selector, _owner, countryID),
            abi.encode(true)
        );
        vm.mockCall(
            KINTO_ID_ADDRESS,
            abi.encodeWithSelector(IKintoID.hasTrait.selector, _user, countryID),
            abi.encode(true)
        );

        // Set country list and switch to Allow Mode
        uint16[] memory countries = new uint16[](1);
        countries[0] = countryID;
        vm.prank(_owner);
        _koban.setCountryList(countries);
        vm.prank(_owner);
        _koban.setCountryListMode(true);

        // Mint tokens to senderWallet
        vm.startPrank(_owner);
        _koban.mint(senderWallet, 1_000e18);
        vm.stopPrank();

        // Attempt to transfer
        vm.prank(senderWallet);
        vm.expectRevert(abi.encodeWithSelector(KintoKoban.TransferRestricted.selector, uint8(1)));
        _koban.transfer(recipientWallet, 500e18);
    }

    /**
     * @notice Test transferring tokens when country restrictions are not met, expecting a revert.
     */
    function testTransfer_CountryRestriction_Revert() public {
        address senderWallet = address(0x1001);
        address recipientWallet = address(0x1002);

        // Mock the walletTs to return non-zero timestamps
        uint256 currentTime = block.timestamp;
        vm.mockCall(
            WALLET_FACTORY_ADDRESS,
            abi.encodeWithSelector(IKintoWalletFactory.walletTs.selector, senderWallet),
            abi.encode(currentTime)
        );
        vm.mockCall(
            WALLET_FACTORY_ADDRESS,
            abi.encodeWithSelector(IKintoWalletFactory.walletTs.selector, recipientWallet),
            abi.encode(currentTime)
        );

        // Mock the owners(0) call on sender and recipient wallets
        vm.mockCall(
            senderWallet,
            abi.encodeWithSelector(IKintoWallet.owners.selector, 0),
            abi.encode(_owner)
        );
        vm.mockCall(
            recipientWallet,
            abi.encodeWithSelector(IKintoWallet.owners.selector, 0),
            abi.encode(_user)
        );

        // Mock KYC status
        vm.mockCall(
            KINTO_ID_ADDRESS,
            abi.encodeWithSelector(IKintoID.isKYC.selector, _owner),
            abi.encode(true)
        );
        vm.mockCall(
            KINTO_ID_ADDRESS,
            abi.encodeWithSelector(IKintoID.isKYC.selector, _user),
            abi.encode(true)
        );

        // Mock country traits: Recipient does not have the required trait
        uint16 countryID = 1;
        vm.mockCall(
            KINTO_ID_ADDRESS,
            abi.encodeWithSelector(IKintoID.hasTrait.selector, _owner, countryID),
            abi.encode(true)
        );
        vm.mockCall(
            KINTO_ID_ADDRESS,
            abi.encodeWithSelector(IKintoID.hasTrait.selector, _user, countryID),
            abi.encode(false)
        );

        // Set country list and switch to Allow Mode
        uint16[] memory countries = new uint16[](1);
        countries[0] = countryID;
        vm.prank(_owner);
        _koban.setCountryList(countries);
        vm.prank(_owner);
        _koban.setCountryListMode(true);

        // Mint tokens to senderWallet
        vm.startPrank(_owner);
        _koban.mint(senderWallet, 1_000e18);
        vm.stopPrank();

        // Attempt to transfer
        vm.prank(senderWallet);
        vm.expectRevert(abi.encodeWithSelector(KintoKoban.TransferRestricted.selector, uint8(2)));
        _koban.transfer(recipientWallet, 500e18);
    }

    /* ============ Country List Management Tests ============ */

    /**
     * @notice Test setting the country list successfully by the owner.
     */
    function testSetCountryList_Success() public {
        vm.startPrank(_owner);
        uint16[] memory countries = new uint16[](3);
        countries[0] = 1;
        countries[1] = 2;
        countries[2] = 3;
        _koban.setCountryList(countries);
        // Verify the bitmaps
        uint256[4] memory bitmaps = _koban.getCountryBitmaps();
        uint256 expectedBitmap = (1 << 1) | (1 << 2) | (1 << 3);
        assertEq(bitmaps[0], expectedBitmap);
        vm.stopPrank();
    }

    /**
     * @notice Test that a non-owner cannot set the country list, expecting a revert.
     */
    function testSetCountryList_CallerNotOwner_Revert() public {
        uint16[] memory countries = new uint16[](1);
        countries[0] = 1;
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, address(this)));
        _koban.setCountryList(countries);
    }

    /**
     * @notice Test setting the country list mode successfully by the owner.
     */
    function testSetCountryListMode_Success() public {
        vm.startPrank(_owner);
        _koban.setCountryListMode(true);
        assertTrue(_koban.allowMode());
        _koban.setCountryListMode(false);
        assertFalse(_koban.allowMode());
        vm.stopPrank();
    }

    /**
     * @notice Test that a non-owner cannot set the country list mode, expecting a revert.
     */
    function testSetCountryListMode_CallerNotOwner_Revert() public {
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, address(this)));
        _koban.setCountryListMode(true);
    }

    /* ============ Utility Function Tests ============ */

    /**
     * @notice Test the utility function to get token details.
     */
    function testGetTokenDetails() public {
        (string memory name, string memory symbol, uint256 totalSupply) = _koban.getTokenDetails();
        assertEq(name, "Kinto Koban");
        assertEq(symbol, "KBON");
        assertEq(totalSupply, 0);
    }

    /* ============ Upgrade Authorization Tests ============ */

    /**
    * @notice Test that a non-owner cannot authorize a contract upgrade, expecting a revert.
    */
    function testAuthorizeUpgrade_CallerNotOwner_Revert() public {
        // Deploy a new implementation contract
        KintoKoban newImplementation = new KintoKoban(1_000_000e18, 10_000e18);

        // Simulate a non-owner caller (e.g., _user)
        vm.startPrank(_user);

        // Expect revert with UUPSUnauthorizedCall error
        vm.expectRevert(abi.encodeWithSelector(UUPSUnauthorizedCall.selector, _user));

        // Call upgradeTo via the proxy using a low-level call
        address(_koban).call(
            abi.encodeWithSignature("upgradeTo(address)", address(newImplementation))
        );

        vm.stopPrank();
    }

    /* ============ Total Supply Override Tests ============ */

    /**
     * @notice Test that totalSupply adheres to the MAX_SUPPLY_LIMIT.
     */
    function testTotalSupply_WithinLimit() public {
        vm.startPrank(_owner);
        _koban.mint(_user, 500_000e18);
        assertEq(_koban.totalSupply(), 500_000e18);
        vm.stopPrank();
    }

    /**
     * @notice Test that exceeding the total supply limit reverts with the correct error.
     */
    function testTotalSupply_ExceedsLimit_Revert() public {
        vm.startPrank(_owner);
        _koban.mint(_user, 1_000_000e18);
        uint256 attemptedSupply = _koban.totalSupply() + 1;
        vm.expectRevert(abi.encodeWithSelector(KintoKoban.ExceedsMaxSupply.selector, attemptedSupply));
        _koban.mint(_user, 1);
        vm.stopPrank();
    }

    /* ============ Edge Case Tests ============ */

    /**
     * @notice Test setting an empty country list removes all country restrictions.
     */
    function testSetCountryList_EmptyList() public {
        address senderWallet = address(0x1001);
        address recipientWallet = address(0x1002);

        // Mock the walletTs to return non-zero timestamps
        uint256 currentTime = block.timestamp;
        vm.mockCall(
            WALLET_FACTORY_ADDRESS,
            abi.encodeWithSelector(IKintoWalletFactory.walletTs.selector, senderWallet),
            abi.encode(currentTime)
        );
        vm.mockCall(
            WALLET_FACTORY_ADDRESS,
            abi.encodeWithSelector(IKintoWalletFactory.walletTs.selector, recipientWallet),
            abi.encode(currentTime)
        );

        // Mock the owners(0) call on sender and recipient wallets
        vm.mockCall(
            senderWallet,
            abi.encodeWithSelector(IKintoWallet.owners.selector, 0),
            abi.encode(_owner)
        );
        vm.mockCall(
            recipientWallet,
            abi.encodeWithSelector(IKintoWallet.owners.selector, 0),
            abi.encode(_user)
        );

        // Mock KYC status
        vm.mockCall(
            KINTO_ID_ADDRESS,
            abi.encodeWithSelector(IKintoID.isKYC.selector, _owner),
            abi.encode(true)
        );
        vm.mockCall(
            KINTO_ID_ADDRESS,
            abi.encodeWithSelector(IKintoID.isKYC.selector, _user),
            abi.encode(true)
        );

        // Set country list to empty and switch to Allow Mode
        vm.prank(_owner);
        _koban.setCountryList(new uint16[](0));
        vm.prank(_owner);
        _koban.setCountryListMode(true);

        // Retrieve the country bitmaps
        uint256[4] memory bitmaps = _koban.getCountryBitmaps();
        for (uint8 i = 0; i < 4; i++) {
            assertEq(bitmaps[i], 0);
        }

        // Mint tokens to senderWallet
        vm.startPrank(_owner);
        _koban.mint(senderWallet, 1_000e18);
        vm.stopPrank();

        // Attempt to transfer should fail due to country restrictions in Allow Mode with empty list
        vm.prank(senderWallet);
        vm.expectRevert(abi.encodeWithSelector(KintoKoban.TransferRestricted.selector, uint8(2)));
        _koban.transfer(recipientWallet, 500e18);

        // Switch to Deny Mode as owner
        vm.prank(_owner);
        _koban.setCountryListMode(false);

        // Transfer tokens should succeed now
        vm.prank(senderWallet);
        bool success = _koban.transfer(recipientWallet, 500e18);
        assertTrue(success);
        assertEq(_koban.balanceOf(recipientWallet), 500e18);
    }

    /**
     * @notice Test transitioning between allow and deny modes and their impact on transfers.
     */
    function testSetCountryListMode_Transition() public {
        address senderWallet = address(0x1001);
        address recipientWallet = address(0x1002);

        // Mock the walletTs to return non-zero timestamps
        uint256 currentTime = block.timestamp;
        vm.mockCall(
            WALLET_FACTORY_ADDRESS,
            abi.encodeWithSelector(IKintoWalletFactory.walletTs.selector, senderWallet),
            abi.encode(currentTime)
        );
        vm.mockCall(
            WALLET_FACTORY_ADDRESS,
            abi.encodeWithSelector(IKintoWalletFactory.walletTs.selector, recipientWallet),
            abi.encode(currentTime)
        );

        // Mock the owners(0) call on sender and recipient wallets
        vm.mockCall(
            senderWallet,
            abi.encodeWithSelector(IKintoWallet.owners.selector, 0),
            abi.encode(_owner)
        );
        vm.mockCall(
            recipientWallet,
            abi.encodeWithSelector(IKintoWallet.owners.selector, 0),
            abi.encode(_user)
        );

        // Mock KYC status
        vm.mockCall(
            KINTO_ID_ADDRESS,
            abi.encodeWithSelector(IKintoID.isKYC.selector, _owner),
            abi.encode(true)
        );
        vm.mockCall(
            KINTO_ID_ADDRESS,
            abi.encodeWithSelector(IKintoID.isKYC.selector, _user),
            abi.encode(true)
        );

        // Mock country traits
        uint16 countryID = 1;
        vm.mockCall(
            KINTO_ID_ADDRESS,
            abi.encodeWithSelector(IKintoID.hasTrait.selector, _owner, countryID),
            abi.encode(true)
        );
        vm.mockCall(
            KINTO_ID_ADDRESS,
            abi.encodeWithSelector(IKintoID.hasTrait.selector, _user, countryID),
            abi.encode(true)
        );

        // Set country list and switch to Allow Mode
        uint16[] memory countries = new uint16[](1);
        countries[0] = countryID;
        vm.prank(_owner);
        _koban.setCountryList(countries);
        vm.prank(_owner);
        _koban.setCountryListMode(true);

        // Mint tokens to senderWallet
        vm.startPrank(_owner);
        _koban.mint(senderWallet, 1_000e18);
        vm.stopPrank();

        // Transfer should succeed in Allow Mode
        vm.prank(senderWallet);
        bool success = _koban.transfer(recipientWallet, 500e18);
        assertTrue(success);
        assertEq(_koban.balanceOf(recipientWallet), 500e18);

        // Switch to Deny Mode
        vm.prank(_owner);
        _koban.setCountryListMode(false);

        // Attempt to transfer should now fail due to country restriction
        vm.prank(senderWallet);
        vm.expectRevert(abi.encodeWithSelector(KintoKoban.TransferRestricted.selector, uint8(2)));
        _koban.transfer(recipientWallet, 500e18);
    }
}
