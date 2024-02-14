// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@oz/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@oz/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@oz/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract InitializableCounter is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address initialOwner) public initializer {
        __Ownable_init(initialOwner);
        __UUPSUpgradeable_init();
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
