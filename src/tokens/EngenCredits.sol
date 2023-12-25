// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import '@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';

/// @custom:security-contact security@mamorilabs.com
contract EngenCredits is Initializable, ERC20Upgradeable,
  ERC20BurnableUpgradeable, OwnableUpgradeable, ERC20PermitUpgradeable, UUPSUpgradeable {

    /// @dev EIP-20 token name for this token
    string private constant _NAME = 'Engen Credits';

    /// @dev EIP-20 token symbol for this token
    string private constant _SYMBOL = 'ENGEN';

    bool public transfersEnabled;
    bool public burnsEnabled;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() initializer public {
        transfersEnabled = false;
        burnsEnabled = false;
        __ERC20_init(_NAME, _SYMBOL);
        __ERC20Burnable_init();
        __Ownable_init();
        __ERC20Permit_init(_NAME);
        __UUPSUpgradeable_init();
    }

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }

    function setTransfersEnabled(bool _transfersEnabled) public onlyOwner {
        require(!transfersEnabled, 'Engen Transfers Already enabled');
        transfersEnabled = _transfersEnabled;
    }
    
    function setBurnsEnabled(bool _burnsEnabled) public onlyOwner {
        require(!burnsEnabled, 'Engen Burns Already enabled');
        burnsEnabled = _burnsEnabled;
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        onlyOwner
        override
    {}

    function _beforeTokenTransfer(address from, address to, uint256 amount)
        internal
        override(ERC20Upgradeable)
    {
        super._beforeTokenTransfer(from, to, amount);
        require(
            from == address(0) ||  // mint
            (to == address(0) && burnsEnabled) ||    // burn
            transfersEnabled,
            'Engen Transfers Disabled');
    }
}
