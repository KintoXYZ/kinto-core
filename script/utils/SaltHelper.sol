// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {LibString} from "solady/utils/LibString.sol";
import {Script} from "forge-std/Script.sol";

contract SaltHelper is Script {
    using LibString for bytes;

    function mineSalt(bytes32 initCodeHash, string memory startsWith)
        public
        returns (bytes32 salt, address expectedAddress)
    {
        string[] memory args = new string[](6);
        args[0] = "cast";
        args[1] = "create2";
        args[2] = "--starts-with";
        args[3] = startsWith;
        args[4] = "--init-code-hash";
        args[5] = LibString.toHexStringNoPrefix(uint256(initCodeHash), 32);
        string memory result = string(vm.ffi(args));

        uint256 addressIndex = LibString.indexOf(result, "Address: ");
        string memory addressStr = LibString.slice(result, addressIndex + 9, addressIndex + 9 + 42);
        expectedAddress = vm.parseAddress(addressStr);

        uint256 saltIndex = LibString.indexOf(result, "Salt: ");
        string memory saltStr = LibString.slice(result, saltIndex + 6, saltIndex + 6 + 66);
        salt = bytes32(vm.parseUint(saltStr));
    }
}
