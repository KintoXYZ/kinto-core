// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "src/tokens/KintoKoban.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title MockKintoID
 * @notice Mock contract to simulate KYC and trait functionality for testing KintoKoban.
 */
contract MockKintoID {
    mapping(address => bool) private _isKYCed;
    mapping(address => mapping(uint16 => bool)) private _traits;

    function isKYC(address account) external view returns (bool) {
        return _isKYCed[account];
    }

    function hasTrait(address account, uint16 traitId) external view returns (bool) {
        return _traits[account][traitId];
    }

    // Mock functions to set KYC status and traits
    function setKYC(address account, bool status) external {
        _isKYCed[account] = status;
    }

    function setTrait(address account, uint16 traitId, bool status) external {
        _traits[account][traitId] = status;
    }
}

/**
 * @title MockKintoWalletFactory
 * @notice Mock contract for IKintoWalletFactory interface.
 */
contract MockKintoWalletFactory {
// Empty mock for testing purposes
}

/**
 * @title MockKintoWallet
 * @notice Mock contract to simulate wallet ownership functionality for testing KintoKoban.
 */
contract MockKintoWallet {
    mapping(uint256 => address) public owners;

    // Function to set an owner at a specific index
    function setOwner(uint256 index, address owner) external {
        owners[index] = owner;
    }
}

/**
 * @title KintoKobanTest
 * @notice Test suite for the KintoKoban contract.
 */
contract KintoKobanTest is Test {
    KintoKoban internal _koban;

    // Mock contracts
    MockKintoID internal _mockKintoID;
    MockKintoWalletFactory internal _mockWalletFactory;

    // Test accounts
    uint256 internal _ownerPk = 1;
    address internal _owner = vm.addr(_ownerPk);

    uint256 internal _userPk = 2;
    address internal _user = vm.addr(_userPk);

    /**
     * @notice Setup function to initialize the KintoKoban contract and deploy mocks.
     */
    function setUp() public {
        // Deploy mock contracts
        _mockKintoID = new MockKintoID();
        _mockWalletFactory = new MockKintoWalletFactory();

        // Deploy the implementation contract
        KintoKoban kobanImplementation = new KintoKoban();

        // Prepare initialization data
        bytes memory initData = abi.encodeWithSignature(
            "initialize(string,string,address,address,uint256,uint256)",
            "Kinto Koban",
            "KBON",
            address(_mockWalletFactory),
            address(_mockKintoID),
            1_000_000e18, // MAX_SUPPLY_LIMIT
            10_000e18 // TOTAL_TRANSFER_LIMIT
        );

        // Deploy the proxy pointing to the implementation
        vm.startPrank(_owner);
        ERC1967Proxy proxy = new ERC1967Proxy(address(kobanImplementation), initData);
        _koban = KintoKoban(address(proxy));
        vm.stopPrank();
    }

    /* ============ Initialization Tests ============ */

    /**
     * @notice Test that the contract initializes with correct parameters.
     */
    function testInitialization() public {
        assertEq(_koban.name(), "Kinto Koban");
        assertEq(_koban.symbol(), "KBON");
        assertEq(_koban.owner(), _owner);
        assertEq(_koban.MAX_SUPPLY_LIMIT(), 1_000_000e18);
        assertEq(_koban.TOTAL_TRANSFER_LIMIT(), 10_000e18);
        assertEq(_koban.allowMode(), false);
        assertEq(_koban.totalSupply(), 0);
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
        vm.expectRevert("Ownable: caller is not the owner");
        _koban.mint(_user, 100e18);
    }

    /* ============ Transfer Tests ============ */

    /**
     * @notice Test a successful token transfer adhering to all restrictions.
     */
    function testTransfer_Success() public {
        // Create sender and recipient wallets
        MockKintoWallet senderWallet = new MockKintoWallet();
        senderWallet.setOwner(0, _owner);
        MockKintoWallet recipientWallet = new MockKintoWallet();
        recipientWallet.setOwner(0, _user);

        // Mint tokens to senderWallet
        vm.startPrank(_owner);
        _koban.mint(address(senderWallet), 50_000e18);
        vm.stopPrank();

        // Mock KYC status
        _mockKintoID.setKYC(_owner, true);
        _mockKintoID.setKYC(_user, true);

        // Mock country traits
        _mockKintoID.setTrait(_owner, 1, true); // Country ID 1
        _mockKintoID.setTrait(_user, 1, true);

        // Set country list and switch to Allow Mode
        uint256[] memory countries = new uint256[](1);
        countries[0] = 1;
        vm.prank(_owner);
        _koban.setCountryList(countries);
        vm.prank(_owner);
        _koban.setCountryListMode(true); // **Added this line**

        // Transfer tokens
        vm.startPrank(address(senderWallet));
        bool success = _koban.transfer(address(recipientWallet), 500e18);
        assertTrue(success);
        assertEq(_koban.balanceOf(address(recipientWallet)), 500e18);
        vm.stopPrank();
    }

    /**
     * @notice Test transferring tokens that exceed the total transfer limit, expecting a revert.
     */
    function testTransfer_ExceedsTransferLimit_Revert() public {
        // Create sender and recipient wallets
        MockKintoWallet senderWallet = new MockKintoWallet();
        senderWallet.setOwner(0, _owner);
        MockKintoWallet recipientWallet = new MockKintoWallet();
        recipientWallet.setOwner(0, _user);

        // Mint tokens to senderWallet
        vm.startPrank(_owner);
        _koban.mint(address(senderWallet), 20_000e18);
        vm.stopPrank();

        // Mock KYC status
        _mockKintoID.setKYC(_owner, true);
        _mockKintoID.setKYC(_user, true);

        // Mock country traits
        _mockKintoID.setTrait(_owner, 1, true);
        _mockKintoID.setTrait(_user, 1, true);

        // Set country list
        uint256[] memory countries = new uint256[](1);
        countries[0] = 1;
        vm.prank(_owner);
        _koban.setCountryList(countries);

        // Attempt to transfer exceeding TOTAL_TRANSFER_LIMIT
        vm.startPrank(address(senderWallet));
        vm.expectRevert(abi.encodeWithSelector(KintoKoban.TransferRestricted.selector, uint8(3)));
        _koban.transfer(address(recipientWallet), 10_001e18);
        vm.stopPrank();
    }

    /**
     * @notice Test transferring tokens when the recipient is not KYCed, expecting a revert.
     */
    function testTransfer_NotKYCed_Revert() public {
        // Create sender and recipient wallets
        MockKintoWallet senderWallet = new MockKintoWallet();
        senderWallet.setOwner(0, _owner);
        MockKintoWallet recipientWallet = new MockKintoWallet();
        recipientWallet.setOwner(0, _user);

        // Mint tokens to senderWallet
        vm.startPrank(_owner);
        _koban.mint(address(senderWallet), 1000e18);
        vm.stopPrank();

        // Mock KYC status
        _mockKintoID.setKYC(_owner, true);
        _mockKintoID.setKYC(_user, false); // Recipient not KYCed

        // Mock country traits
        _mockKintoID.setTrait(_owner, 1, true);
        _mockKintoID.setTrait(_user, 1, true);

        // Set country list
        uint256[] memory countries = new uint256[](1);
        countries[0] = 1;
        vm.prank(_owner);
        _koban.setCountryList(countries);

        // Attempt to transfer
        vm.startPrank(address(senderWallet));
        vm.expectRevert(abi.encodeWithSelector(KintoKoban.TransferRestricted.selector, uint8(1)));
        _koban.transfer(address(recipientWallet), 500e18);
        vm.stopPrank();
    }

    /**
     * @notice Test transferring tokens when country restrictions are not met, expecting a revert.
     */
    function testTransfer_CountryRestriction_Revert() public {
        // Create sender and recipient wallets
        MockKintoWallet senderWallet = new MockKintoWallet();
        senderWallet.setOwner(0, _owner);
        MockKintoWallet recipientWallet = new MockKintoWallet();
        recipientWallet.setOwner(0, _user);

        // Mint tokens to senderWallet
        vm.startPrank(_owner);
        _koban.mint(address(senderWallet), 1000e18);
        vm.stopPrank();

        // Mock KYC status
        _mockKintoID.setKYC(_owner, true);
        _mockKintoID.setKYC(_user, true);

        // Mock country traits - user does not have required trait
        _mockKintoID.setTrait(_owner, 1, true);
        _mockKintoID.setTrait(_user, 1, false);

        // Set country list
        uint256[] memory countries = new uint256[](1);
        countries[0] = 1;
        vm.prank(_owner);
        _koban.setCountryList(countries);

        // Attempt to transfer
        vm.startPrank(address(senderWallet));
        vm.expectRevert(abi.encodeWithSelector(KintoKoban.TransferRestricted.selector, uint8(2)));
        _koban.transfer(address(recipientWallet), 500e18);
        vm.stopPrank();
    }

    /* ============ Country List Management Tests ============ */

    /**
     * @notice Test setting the country list successfully by the owner.
     */
    function testSetCountryList_Success() public {
        vm.startPrank(_owner);
        uint256[] memory countries = new uint256[](3);
        countries[0] = 1;
        countries[1] = 2;
        countries[2] = 3;
        _koban.setCountryList(countries);
        assertEq(_koban.countryList(0), 1);
        assertEq(_koban.countryList(1), 2);
        assertEq(_koban.countryList(2), 3);
        assertEq(_koban.getCountryListLength(), 3);
        vm.stopPrank();
    }

    /**
     * @notice Test that a non-owner cannot set the country list, expecting a revert.
     */
    function testSetCountryList_CallerNotOwner_Revert() public {
        uint256[] memory countries = new uint256[](1);
        countries[0] = 1;
        vm.expectRevert("Ownable: caller is not the owner");
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
        vm.expectRevert("Ownable: caller is not the owner");
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
     * @notice Test that the owner can authorize a contract upgrade.
     */
    function testAuthorizeUpgrade_Success() public {
        // Deploy a new implementation contract
        KintoKoban newImplementation = new KintoKoban();
        vm.startPrank(_owner);
        _koban.upgradeTo(address(newImplementation));
        vm.stopPrank();
    }

    /**
     * @notice Test that a non-owner cannot authorize a contract upgrade, expecting a revert.
     */
    function testAuthorizeUpgrade_CallerNotOwner_Revert() public {
        // Deploy a new implementation contract
        KintoKoban newImplementation = new KintoKoban();
        vm.expectRevert("Ownable: caller is not the owner");
        _koban.upgradeTo(address(newImplementation));
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

    /* ============ KYC and Country Traits Mocking Tests ============ */

    /**
     * @notice Test the interaction between KYC status, country traits, and transfer restrictions.
     */
    function testKYC_Mocking() public {
        // Create sender and recipient wallets
        MockKintoWallet senderWallet = new MockKintoWallet();
        senderWallet.setOwner(0, _owner);
        MockKintoWallet recipientWallet = new MockKintoWallet();
        recipientWallet.setOwner(0, _user);

        // Mint tokens to senderWallet
        vm.startPrank(_owner);
        _koban.mint(address(senderWallet), 1000e18);
        vm.stopPrank();

        // Initially, no KYC set
        vm.startPrank(address(senderWallet));
        vm.expectRevert(abi.encodeWithSelector(KintoKoban.TransferRestricted.selector, uint8(1)));
        _koban.transfer(address(recipientWallet), 100e18);
        vm.stopPrank();

        // Set KYC for both owners
        _mockKintoID.setKYC(_owner, true);
        _mockKintoID.setKYC(_user, true);

        // Set country traits
        _mockKintoID.setTrait(_owner, 1, true);
        _mockKintoID.setTrait(_user, 1, true);

        // Set country list and switch to Allow Mode
        uint256[] memory countries = new uint256[](1);
        countries[0] = 1;
        vm.prank(_owner);
        _koban.setCountryList(countries);
        vm.prank(_owner);
        _koban.setCountryListMode(true); // **Added this line**

        // Transfer should now succeed
        vm.startPrank(address(senderWallet));
        bool success = _koban.transfer(address(recipientWallet), 100e18);
        assertTrue(success);
        assertEq(_koban.balanceOf(address(recipientWallet)), 100e18);
        vm.stopPrank();
    }

    /* ============ Edge Case Tests ============ */

    /**
     * @notice Test setting an empty country list removes all country restrictions.
     */
    function testSetCountryList_EmptyList() public {
        // Create sender and recipient wallets
        MockKintoWallet senderWallet = new MockKintoWallet();
        senderWallet.setOwner(0, _owner);
        MockKintoWallet recipientWallet = new MockKintoWallet();
        recipientWallet.setOwner(0, _user);

        vm.startPrank(_owner);
        uint256[] memory countries = new uint256[](0);
        _koban.setCountryList(countries);
        assertEq(_koban.getCountryListLength(), 0);

        // Without any country restrictions, transfers should only depend on KYC and transfer limits
        _koban.mint(address(senderWallet), 1000e18);
        _mockKintoID.setKYC(_owner, true);
        _mockKintoID.setKYC(_user, true);
        vm.stopPrank();

        // Transfer tokens
        vm.startPrank(address(senderWallet));
        bool success = _koban.transfer(address(recipientWallet), 500e18);
        assertTrue(success);
        assertEq(_koban.balanceOf(address(recipientWallet)), 500e18);
        vm.stopPrank();
    }

    /**
     * @notice Test transitioning between allow and deny modes and their impact on transfers.
     */
    function testSetCountryListMode_Transition() public {
        // Step 1: Initialize the country list and set to Allow Mode as the owner
        vm.startPrank(_owner);
        uint256[] memory countries = new uint256[](2);
        countries[0] = 1;
        countries[1] = 2;
        _koban.setCountryList(countries);
        _koban.setCountryListMode(true); // Switch to Allow Mode
        vm.stopPrank(); // **Stop the owner prank**

        // Step 2: Set KYC status and country traits for both owner and user
        // Since setKYC and setTrait are external functions on the mock contracts,
        // they need to be called from an account that has permissions to do so.
        // Assuming the test contract has the necessary permissions.
        _mockKintoID.setKYC(_owner, true);
        _mockKintoID.setKYC(_user, true);
        _mockKintoID.setTrait(_owner, 1, true);
        _mockKintoID.setTrait(_user, 1, true);

        // Step 3: Deploy and set up sender and recipient wallets
        MockKintoWallet senderWallet = new MockKintoWallet();
        senderWallet.setOwner(0, _owner);
        MockKintoWallet recipientWallet = new MockKintoWallet();
        recipientWallet.setOwner(0, _user);

        // Step 4: Mint tokens to the senderWallet as the owner
        vm.startPrank(_owner);
        _koban.mint(address(senderWallet), 1000e18);
        vm.stopPrank(); // **Stop the owner prank**

        // Step 5: Perform a successful transfer in Allow Mode
        vm.startPrank(address(senderWallet));
        bool success = _koban.transfer(address(recipientWallet), 500e18);
        assertTrue(success, "Transfer should succeed in Allow Mode");
        assertEq(_koban.balanceOf(address(recipientWallet)), 500e18, "Recipient should receive 500 KBON");
        vm.stopPrank(); // **Stop the senderWallet prank**

        // Step 6: Switch to Deny Mode as the owner
        vm.startPrank(_owner);
        _koban.setCountryListMode(false); // Switch to Deny Mode
        vm.stopPrank(); // **Stop the owner prank**

        // Step 7: Attempt a transfer that should now fail in Deny Mode
        vm.startPrank(address(senderWallet));
        vm.expectRevert(abi.encodeWithSelector(KintoKoban.TransferRestricted.selector, uint8(2)));
        _koban.transfer(address(recipientWallet), 500e18);
        vm.stopPrank(); // **Stop the senderWallet prank**
    }
}
