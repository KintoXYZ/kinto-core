// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

library ArrayHelpers {
    function toMemoryArray(bool[1] memory array) internal pure returns (bool[] memory) {
        bool[] memory ret = new bool[](1);
        ret[0] = array[0];
        return ret;
    }

    function toMemoryArray(bool[2] memory array) internal pure returns (bool[] memory) {
        bool[] memory ret = new bool[](2);
        ret[0] = array[0];
        ret[1] = array[1];
        return ret;
    }

    function toMemoryArray(bool[5] memory array) internal pure returns (bool[] memory) {
        bool[] memory ret = new bool[](5);
        ret[0] = array[0];
        ret[1] = array[1];
        ret[2] = array[2];
        ret[3] = array[3];
        ret[4] = array[4];
        return ret;
    }

    function toMemoryArray(address[1] memory array) internal pure returns (address[] memory) {
        address[] memory ret = new address[](1);
        ret[0] = array[0];
        return ret;
    }

    function toMemoryArray(address[2] memory array) internal pure returns (address[] memory) {
        address[] memory ret = new address[](2);
        ret[0] = array[0];
        ret[1] = array[1];
        return ret;
    }

    function toMemoryArray(address[3] memory array) internal pure returns (address[] memory) {
        address[] memory ret = new address[](3);
        ret[0] = array[0];
        ret[1] = array[1];
        ret[2] = array[2];
        return ret;
    }

    function toMemoryArray(address[4] memory array) internal pure returns (address[] memory) {
        address[] memory ret = new address[](4);
        ret[0] = array[0];
        ret[1] = array[1];
        ret[2] = array[2];
        ret[3] = array[3];
        return ret;
    }

    function toMemoryArray(address[5] memory array) internal pure returns (address[] memory) {
        address[] memory ret = new address[](5);
        ret[0] = array[0];
        ret[1] = array[1];
        ret[2] = array[2];
        ret[3] = array[3];
        ret[4] = array[4];
        return ret;
    }

    function toMemoryArray(address[7] memory array) internal pure returns (address[] memory) {
        address[] memory ret = new address[](7);
        ret[0] = array[0];
        ret[1] = array[1];
        ret[2] = array[2];
        ret[3] = array[3];
        ret[4] = array[4];
        ret[5] = array[5];
        ret[6] = array[6];
        return ret;
    }

    function toMemoryArray(address[8] memory array) internal pure returns (address[] memory) {
        address[] memory ret = new address[](8);
        ret[0] = array[0];
        ret[1] = array[1];
        ret[2] = array[2];
        ret[3] = array[3];
        ret[4] = array[4];
        ret[5] = array[5];
        ret[6] = array[6];
        ret[7] = array[7];
        return ret;
    }

    function toMemoryArray(uint256[1] memory array) internal pure returns (uint256[] memory) {
        uint256[] memory ret = new uint256[](1);
        ret[0] = array[0];
        return ret;
    }

    function toMemoryArray(uint256[2] memory array) internal pure returns (uint256[] memory) {
        uint256[] memory ret = new uint256[](2);
        ret[0] = array[0];
        ret[1] = array[1];
        return ret;
    }

    function toMemoryArray(uint256[3] memory array) internal pure returns (uint256[] memory) {
        uint256[] memory ret = new uint256[](3);
        ret[0] = array[0];
        ret[1] = array[1];
        ret[2] = array[2];
        return ret;
    }

    /**
     * @dev Casts an array of uint256 to int256, setting the sign of the result according to the `positive` flag,
     * without checking whether the values fit in the signed 256 bit range.
     */
    function unsafeCastToInt256(uint256[] memory values, bool positive)
        internal
        pure
        returns (int256[] memory signedValues)
    {
        signedValues = new int256[](values.length);
        for (uint256 i = 0; i < values.length; i++) {
            signedValues[i] = positive ? int256(values[i]) : -int256(values[i]);
        }
    }

    /// @dev Returns addresses as an array IERC20[] memory
    function asIERC20(address[] memory addresses) internal pure returns (IERC20[] memory tokens) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            tokens := addresses
        }
    }
}
