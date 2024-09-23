// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "../interfaces/IKintoWalletFactory.sol";
import "../interfaces/IKintoID.sol";

/**
 * @title KintoKoban
 * @notice ERC20 token with Kinto functionalities for KYC and country restrictions. Compatible with ERC1404.
 */
contract KintoKoban is Initializable, ERC20Upgradeable, OwnableUpgradeable, UUPSUpgradeable {
    uint256 public MAX_SUPPLY_LIMIT;
    uint256 public TOTAL_TRANSFER_LIMIT;

    IKintoWalletFactory public walletFactory;
    IKintoID public kintoID;

    // Country list and mode (true for allow, false for deny)
    uint256[] public countryList; // Array of country IDs
    bool public allowMode; // true = allow listed countries, false = deny listed countries

    // Custom errors
    error TransferRestricted(uint8 restrictionCode);
    error ExceedsMaxSupply(uint256 attemptedSupply);
    error ExceedsTransferLimit(uint256 attemptedTransfer);

    /**
     * @notice Initializer to initialize the token and KintoID
     * @param _name Name of the token
     * @param _symbol Symbol of the token
     * @param _walletFactory Address of the KintoWalletFactory contract
     * @param _kintoID Address of the KintoID contract
     * @param _maxSupply Maximum supply of tokens
     * @param _maxTransferAmount Maximum amount allowed for transfers
     */
    function initialize(
        string memory _name,
        string memory _symbol,
        address _walletFactory,
        address _kintoID,
        uint256 _maxSupply,
        uint256 _maxTransferAmount
    ) public initializer {
        __ERC20_init(_name, _symbol);
        __Ownable_init();
        __UUPSUpgradeable_init();

        walletFactory = IKintoWalletFactory(_walletFactory);
        kintoID = IKintoID(_kintoID);
        MAX_SUPPLY_LIMIT = _maxSupply;
        TOTAL_TRANSFER_LIMIT = _maxTransferAmount;
        allowMode = false; // Blacklist by default (will allow all since the list is empty)
    }

    /**
     * @notice Override totalSupply to enforce MAX_SUPPLY_LIMIT
     * @return uint256 total supply of tokens
     */
    function totalSupply() public view override returns (uint256) {
        uint256 supply = super.totalSupply();
        require(supply <= MAX_SUPPLY_LIMIT, "Total supply exceeds maximum limit");
        return supply;
    }

    /**
     * @notice Mint function with MAX_SUPPLY_LIMIT enforcement
     * @param to Address to mint tokens to
     * @param amount Amount of tokens to mint
     */
    function mint(address to, uint256 amount) external onlyOwner {
        if (totalSupply() + amount > MAX_SUPPLY_LIMIT) {
            revert ExceedsMaxSupply(totalSupply() + amount);
        }
        _mint(to, amount);
    }

    /**
     * @notice Transfer function that checks KYC status and country restrictions before allowing transfer
     * @param recipient Address of the recipient
     * @param amount Amount of tokens to transfer
     * @return bool indicating success
     */
    function transfer(address recipient, uint256 amount) public override returns (bool) {
        uint8 restrictionCode = detectTransferRestriction(msg.sender, recipient, amount);
        if (restrictionCode != 0) {
            revert TransferRestricted(restrictionCode);
        }
        return super.transfer(recipient, amount);
    }

    /**
     * @notice Detects transfer restrictions based on KYC status, country list, and transfer amount
     * @param from Address of the sender
     * @param to Address of the recipient
     * @param value Amount of tokens to transfer
     * @return uint8 restriction code (0=success, 1=not KYCed, 2=country restriction, 3=exceeds transfer limit)
     */
    function detectTransferRestriction(address from, address to, uint256 value) public view returns (uint8) {
        // Check for total transfer limit
        if (value > TOTAL_TRANSFER_LIMIT) {
            return 3; // Exceeds transfer limit
        }

        // Get the owner of the KintoID NFT for both wallets
        address fromOwner = IKintoWallet(from).owners(0); // Owner of the KintoID for sender
        address toOwner = IKintoWallet(to).owners(0); // Owner of the KintoID for recipient
        // Use kintoID for KYC checks
        if (!kintoID.isKYC(fromOwner) || !kintoID.isKYC(toOwner)) {
            return 1; // Either sender or recipient is not KYCed
        }
        // Check if the sender and recipient have the required country traits
        bool fromFlagged = false;
        bool toFlagged = false;
        for (uint256 i = 0; i < countryList.length; i++) {
            if (kintoID.hasTrait(fromOwner, uint16(countryList[i]))) {
                fromFlagged = true; // Sender has an allowed trait
            }
            if (kintoID.hasTrait(toOwner, uint16(countryList[i]))) {
                toFlagged = true; // Recipient has an allowed trait
            }
        }

        if (allowMode) {
            // Allow mode: both must have at least one allowed trait
            if (!fromFlagged || !toFlagged) {
                return 2; // Either sender or recipient country not allowed
            }
        } else {
            // Deny mode: neither can have an allowed trait
            if (fromFlagged || toFlagged) {
                return 2; // Either sender or recipient country is denied
            }
        }

        return 0; // Success
    }

    /**
     * @notice Returns a human-readable message for the passed restriction code
     * @param restrictionCode The restriction code to interpret
     * @return string A message corresponding to the restriction code
     */
    function messageForTransferRestriction(uint8 restrictionCode) public pure returns (string memory) {
        if (restrictionCode == 0) {
            return "Transfer allowed";
        } else if (restrictionCode == 1) {
            return "Sender or recipient is not KYCed";
        } else if (restrictionCode == 2) {
            return "Transfer restricted by country list";
        } else if (restrictionCode == 3) {
            return "Transfer amount exceeds the maximum allowed limit";
        }
        return "Unknown restriction";
    }

    /**
     * @notice Sets the entire country list
     * @param countryIds An array of country IDs to set
     */
    function setCountryList(uint256[] calldata countryIds) external onlyOwner {
        delete countryList; // Clear the existing list
        for (uint256 i = 0; i < countryIds.length; i++) {
            countryList.push(countryIds[i]);
        }
    }

    /**
     * @notice Returns the length of the country list
     * @return uint256 The length of the country list
     */
    function getCountryListLength() external view returns (uint256) {
        return countryList.length;
    }

    /**
     * @notice Sets the mode for the country list
     * @param _allowMode True to allow listed countries, false to deny listed countries
     */
    function setCountryListMode(bool _allowMode) external onlyOwner {
        allowMode = _allowMode;
    }

    /**
     * @notice Returns the token details
     * @return name, symbol, totalSupply
     */
    function getTokenDetails() external view returns (string memory, string memory, uint256) {
        return (name(), symbol(), totalSupply());
    }

    /**
     * @notice Authorize the upgrade. Only by an owner.
     * @param newImplementation address of the new implementation
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
