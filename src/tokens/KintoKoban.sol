// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../viewers/KYCViewer.sol";

/**
 * @title KintoKoban
 * @notice ERC20 token with Kinto functionalites for KYC and country restrictions. Compatible with ERC1404.
 */
contract KintoKoban is ERC20, Ownable {
    // Max supply of tokens
    uint256 public maxSupply; // Configurable max supply
    uint256 public maxTransferAmount; // Maximum amount allowed for transfers
    KYCViewer public kycViewer;

    // Country list and mode (true for allow, false for deny)
    mapping(uint16 => bool) public countryList;
    bool public allowMode; // true = allow listed countries, false = deny listed countries

    /**
     * @notice Constructor to initialize the token and KYC viewer
     * @param _name Name of the token
     * @param _symbol Symbol of the token
     * @param _kycViewer Address of the KYCViewer contract
     * @param _maxSupply Maximum supply of tokens
     * @param _maxTransferAmount Maximum amount allowed for transfers
     */
    constructor(
        string memory _name,
        string memory _symbol,
        address _kycViewer,
        uint256 _maxSupply,
        uint256 _maxTransferAmount
    ) ERC20(_name, _symbol) {
        kycViewer = KYCViewer(_kycViewer);
        maxSupply = _maxSupply; // Set the max supply
        maxTransferAmount = _maxTransferAmount; // Set the max transfer amount
    }

    /**
     * @notice Public mint function to mint new tokens
     * @param amount Amount of tokens to mint
     */
    function mint(uint256 amount) external onlyOwner {
        require(totalSupply() + amount <= maxSupply, "Minting exceeds max supply");
        _mint(msg.sender, amount);
    }

    /**
     * @notice Transfer function that checks KYC status and country restrictions before allowing transfer
     * @param recipient Address of the recipient
     * @param amount Amount of tokens to transfer
     * @return bool indicating success
     */
    function transfer(address recipient, uint256 amount) public override returns (bool) {
        require(detectTransferRestriction(msg.sender, recipient, amount) == 0, "Transfer restricted");
        return super.transfer(recipient, amount);
    }

    /**
     * @notice Detects transfer restrictions based on KYC status, country list, and transfer amount
     * @param from Address of the sender
     * @param to Address of the recipient
     * @param value Amount of tokens to transfer
     * @return uint8 restriction code (0=success, 1=not KYCed, 2=country restriction, 3=amount restriction)
     */
    function detectTransferRestriction(address from, address to, uint256 value) public view returns (uint8) {
        // Check KYC status for both sender and recipient
        if (!kycViewer.isKYC(from) || !kycViewer.isKYC(to)) {
            return 1; // Either sender or recipient is not KYCed
        }

        // Check country restrictions
        uint16 fromCountryId = kycViewer.getCountry(from);
        uint16 toCountryId = kycViewer.getCountry(to);
        bool isFromListed = countryList[fromCountryId];
        bool isToListed = countryList[toCountryId];

        // Determine if transfer is allowed based on the mode
        if (allowMode != isFromListed || allowMode != isToListed) {
            return 2; // Either sender or recipient country not allowed or denied
        }

        // Check transfer amount restriction
        if (value > maxTransferAmount) {
            return 3; // Transfer amount exceeds the maximum limit
        }

        return 0; // Success
    }

    /**
     * @notice Returns a human-readable message for the passed restriction code
     * @param restrictionCode The restriction code to interpret
     * @return string A message corresponding to the restriction code
     */
    function messageForTransferRestriction(uint8 restrictionCode) public view returns (string memory) {
        if (restrictionCode == 0) {
            return "Transfer allowed";
        } else if (restrictionCode == 1) {
            return "Sender or recipient is not KYCed";
        } else if (restrictionCode == 2) {
            return "Transfer restricted by country list";
        } else if (restrictionCode == 3) {
            return "Transfer amount exceeds the maximum limit";
        }
        return "Unknown restriction";
    }

    /**
     * @notice Adds multiple countries to the country list
     * @param countryIds An array of country IDs to add
     */
    function addToCountryList(uint16[] calldata countryIds) external onlyOwner {
        for (uint256 i = 0; i < countryIds.length; i++) {
            countryList[countryIds[i]] = true;
        }
    }

    /**
     * @notice Removes multiple countries from the country list
     * @param countryIds An array of country IDs to remove
     */
    function removeFromCountryList(uint16[] calldata countryIds) external onlyOwner {
        for (uint256 i = 0; i < countryIds.length; i++) {
            countryList[countryIds[i]] = false;
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
     * @notice Sets the maximum transfer amount
     * @param _maxTransferAmount The maximum amount allowed for transfers
     */
    function setMaxTransferAmount(uint256 _maxTransferAmount) external onlyOwner {
        maxTransferAmount = _maxTransferAmount;
    }

    /**
     * @notice Returns the token details
     * @return name, symbol, totalSupply
     */
    function getTokenDetails() external view returns (string memory, string memory, uint256) {
        return (name(), symbol(), totalSupply());
    }
}
