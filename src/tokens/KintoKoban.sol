// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin-5.0.1/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin-5.0.1/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin-5.0.1/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin-5.0.1/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "../interfaces/IKintoWalletFactory.sol";
import "../interfaces/IKintoID.sol";

/**
 * @title KintoKoban
 * @notice ERC20 token with Kinto functionalities for KYC and country restrictions. Compatible with ERC1404.
 */
contract KintoKoban is Initializable, ERC20Upgradeable, OwnableUpgradeable, UUPSUpgradeable {
    uint256 public immutable MAX_SUPPLY_LIMIT;
    uint256 public immutable TOTAL_TRANSFER_LIMIT;

    IKintoWalletFactory public immutable WALLET_FACTORY;
    IKintoID public immutable KINTO_ID;

    // Country bitmaps and mode (true for allow, false for deny)
    uint256[4] public countryBitmaps; // Each uint256 covers 256 country IDs (0-1023)
    bool public allowMode; // true = allow listed countries, false = deny listed countries

    // Constants for restriction codes
    uint8 constant SUCCESS_CODE = 0;
    uint8 constant NOT_KYCED_CODE = 1;
    uint8 constant COUNTRY_RESTRICTED_CODE = 2;
    uint8 constant EXCEED_TRANSFER_LIMIT_CODE = 3;

    // Custom errors
    error TransferRestricted(uint8 restrictionCode);
    error ExceedsMaxSupply(uint256 attemptedSupply);
    error ExceedsTransferLimit(uint256 attemptedTransfer);

    constructor(uint256 maxSupplyLimit, uint256 totalTransferLimit) {
        //immutable variables must be initialized in the constructor
        WALLET_FACTORY = IKintoWalletFactory(0x8a4720488CA32f1223ccFE5A087e250fE3BC5D75);
        KINTO_ID = IKintoID(0xf369f78E3A0492CC4e96a90dae0728A38498e9c7);
        MAX_SUPPLY_LIMIT = maxSupplyLimit;
        TOTAL_TRANSFER_LIMIT = totalTransferLimit;
    }

    /**
     * @notice Initializer for the contract
     */
    function initialize(string memory name, string memory symbol) public initializer {
        __ERC20_init(name, symbol);
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
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
        if (restrictionCode != SUCCESS_CODE) {
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
            return EXCEED_TRANSFER_LIMIT_CODE; // Exceeds transfer limit
        }

        //use walletFactory to check they are a wallet walletTs > 0
        if (WALLET_FACTORY.walletTs(from) == 0 || WALLET_FACTORY.walletTs(to) == 0) {
            return NOT_KYCED_CODE; // Either sender or recipient is not a wallet
        }
        
        // Get the owner of the KintoID NFT for both wallets
        address fromOwner = IKintoWallet(from).owners(0); // Owner of the KintoID for sender
        address toOwner = IKintoWallet(to).owners(0); // Owner of the KintoID for recipient
        // Use kintoID for KYC checks
        if (!KINTO_ID.isKYC(fromOwner) || !KINTO_ID.isKYC(toOwner)) {
            return NOT_KYCED_CODE; // Either sender or recipient is not KYCed
        }

        // Check if the sender and recipient have the required country traits
        bool fromFlagged = hasAnyCountryTrait(fromOwner);
        bool toFlagged = hasAnyCountryTrait(toOwner);

        if (allowMode) {
            // Allow mode: both must have at least one allowed trait
            if (!fromFlagged || !toFlagged) {
                return COUNTRY_RESTRICTED_CODE; // Either sender or recipient country not allowed
            }
        } else {
            // Deny mode: neither can have an allowed trait
            if (fromFlagged || toFlagged) {
                return COUNTRY_RESTRICTED_CODE; // Either sender or recipient country is denied
            }
        }

        return SUCCESS_CODE; // Success
    }

    /**
     * @notice Checks if a user has any of the traits specified in the country bitmaps
     * @param user The address of the user to check
     * @return bool indicating if the user has any of the country traits
     */
    function hasAnyCountryTrait(address user) internal view returns (bool) {
        for (uint8 bitmapIndex = 0; bitmapIndex < 4; bitmapIndex++) {
            uint256 bitmap = countryBitmaps[bitmapIndex];
            if (bitmap == 0) continue; // Skip empty bitmaps

            // Iterate over the set bits in the bitmap
            for (uint16 bitIndex = 0; bitIndex < 256; bitIndex++) {
                if ((bitmap & (uint256(1) << bitIndex)) != 0) {
                    uint16 traitID = uint16(bitmapIndex * 256 + bitIndex);
                    if (KINTO_ID.hasTrait(user, traitID)) {
                        return true; // User has a trait in the country list
                    }
                }
            }
        }
        return false; // No matching trait found
    }

    /**
     * @notice Returns a human-readable message for the passed restriction code
     * @param restrictionCode The restriction code to interpret
     * @return string A message corresponding to the restriction code
     */
    function messageForTransferRestriction(uint8 restrictionCode) public pure returns (string memory) {
        if (restrictionCode == SUCCESS_CODE) {
            return "Transfer allowed";
        } else if (restrictionCode == NOT_KYCED_CODE) {
            return "Sender or recipient is not KYCed";
        } else if (restrictionCode == COUNTRY_RESTRICTED_CODE) {
            return "Transfer restricted by country list";
        } else if (restrictionCode == EXCEED_TRANSFER_LIMIT_CODE) {
            return "Transfer amount exceeds the maximum allowed limit";
        }
        return "Unknown restriction";
    }

    /**
     * @notice Sets the country list using bitmaps
     * @param countryIds An array of country IDs to set
     */
    function setCountryList(uint16[] calldata countryIds) external onlyOwner {
        // Clear existing bitmaps
        for (uint8 i = 0; i < 4; i++) {
            countryBitmaps[i] = 0;
        }

        for (uint256 i = 0; i < countryIds.length; i++) {
            uint16 countryID = countryIds[i];
            uint8 bitmapIndex;
            uint16 indexWithinBitmap;
            if (countryID <= 255) {
                bitmapIndex = 0;
                indexWithinBitmap = countryID;
            } else if (countryID <= 511) {
                bitmapIndex = 1;
                indexWithinBitmap = countryID - 256;
            } else if (countryID <= 767) {
                bitmapIndex = 2;
                indexWithinBitmap = countryID - 512;
            } else if (countryID <= 1023) {
                bitmapIndex = 3;
                indexWithinBitmap = countryID - 768;
            } else {
                continue;
            }
            countryBitmaps[bitmapIndex] |= uint256(1) << indexWithinBitmap;
        }
    }

    /**
     * @notice Sets the mode for the country list
     * @param _allowMode True to allow listed countries, false to deny listed countries
     */
    function setCountryListMode(bool _allowMode) external onlyOwner {
        allowMode = _allowMode;
    }

    /**
     * @notice Returns the entire countryBitmaps array
     * @return uint256[4] memory array containing the country bitmaps
     */
    function getCountryBitmaps() external view returns (uint256[4] memory) {
        return countryBitmaps;
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
