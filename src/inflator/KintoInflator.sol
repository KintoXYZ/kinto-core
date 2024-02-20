// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../interfaces/IOpInflator.sol";
import "../interfaces/IKintoWallet.sol";

import "@solady/utils/LibZip.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

// TODO: make it ugradeable?
// TODO: consider using assembly for encoding/decoding?
// TODO: consider hardcoding gas params (or using smaller types, also for nonce)
// TODO: consider using IDs instead of names for Kinto contracts

/// @notice Inflator contract for Kinto user operations
/// @dev This contract is responsible for inflating and compressing (off-chain) user operations
/// The first byte of the compressed data is used as follows:
/// 0x01: sender == target (whether the sender is the same as the target) so we don't need to encode the target
/// 0x02: Kinto contract (whether the target is a Kinto contract) so we can use the contract name instead of the address
/// 0x04: selector (whether the selector is `execute` or `executeBatch`) so we don't need to encode the selector
/// 0x08: paymasterAndData (whether to use the SponsorPaymaster or not) so we don't need to encode the paymaster address
/// The rest of the flags are not used.
/// All other UserOperation fields are encoded as is.
contract KintoInflator is IOpInflator, Ownable {
    mapping(string => address) public kintoContracts; // mapping of Kinto contract names to addresses
    mapping(address => string) public kintoNames; // mapping of Kinto contract addresses to names

    event KintoContractSet(string name, address target);

    function inflate(bytes calldata compressed) external view returns (UserOperation memory op) {
        // decompress the data
        bytes memory decompressedData = LibZip.flzDecompress(compressed);

        // deserialize the data
        uint256 cursor = 0; // keep track of the current position in the decompressed data

        // read flags byte
        uint8 flags = uint8(decompressedData[cursor]);
        cursor += 1; // move past the flags byte

        // extract `sender`
        op.sender = _bytesToAddress(_slice(decompressedData, cursor, 20));
        cursor += 20;

        // extract `nonce`
        op.nonce = _bytesToUint256(_slice(decompressedData, cursor, 32));
        cursor += 32;

        // extract `initCode` (notice: we are always using an empty initCode for now)
        op.initCode = bytes("");

        // extract `calldata` (selector, target, value, bytesOp)
        // we skip value since we assume it's always 0

        // 1. extract target
        address target;

        // if second flag is set, it means target is a Kinto contract
        if (flags & 0x02 == 0x02) {
            uint8 nameLength = uint8(decompressedData[cursor]);
            cursor += 1;
            string memory name = string(_slice(decompressedData, cursor, nameLength));
            cursor += nameLength;

            // get contract address from mapping
            target = kintoContracts[name];
        } else {
            // if first flag is set, it means target == sender
            if (flags & 0x01 == 0x01) {
                target = op.sender;
            } else {
                // if target is not a Kinto contract, just extract target address
                target = _bytesToAddress(_slice(decompressedData, cursor, 20));
                cursor += 20;
            }
        }

        // 2. extract bytesOp
        uint256 bytesOpLength = _bytesToUint256(_slice(decompressedData, cursor, 32));
        cursor += 32;
        bytes memory bytesOp = _slice(decompressedData, cursor, bytesOpLength);

        // 3. build `callData`
        // if third flag is set, it means selector is `execute` or `executeBatch`
        if (flags & 0x04 == 0x04) {
            op.callData = abi.encodeCall(IKintoWallet.execute, (target, 0, bytesOp));
        } else {
            address[] memory targets = new address[](1); // TODO: replace
            targets[0] = target;
            uint256[] memory values = new uint256[](1); // TODO: replace
            values[0] = 0;
            bytes[] memory operations = new bytes[](1); // TODO: replace
            operations[0] = bytesOp;

            op.callData = abi.encodeCall(IKintoWallet.executeBatch, (targets, values, operations));
        }
        cursor += bytesOpLength;

        // extract `callGasLimit`
        op.callGasLimit = _bytesToUint256(_slice(decompressedData, cursor, 32));
        cursor += 32;

        // extract `verificationGasLimit`
        op.verificationGasLimit = _bytesToUint256(_slice(decompressedData, cursor, 32));
        cursor += 32;

        // extract `preVerificationGas`
        op.preVerificationGas = _bytesToUint256(_slice(decompressedData, cursor, 32));
        cursor += 32;

        // extract `maxFeePerGas`
        op.maxFeePerGas = _bytesToUint256(_slice(decompressedData, cursor, 32));
        cursor += 32;

        // extract `maxPriorityFeePerGas`
        op.maxPriorityFeePerGas = _bytesToUint256(_slice(decompressedData, cursor, 32));
        cursor += 32;

        // extract `paymasterAndData`
        // if fourth flag is set, it means paymasterAndData is set so we can use the contract stored in the mapping
        if (flags & 0x08 == 0x08) {
            op.paymasterAndData = abi.encodePacked(kintoContracts["SponsorPaymaster"]);
        }

        // decode signature
        uint256 signatureLength = _bytesToUint256(_slice(decompressedData, cursor, 32));
        cursor += 32;
        op.signature = _slice(decompressedData, cursor, signatureLength);
        cursor += signatureLength;

        return op;
    }

    function inflateSimple(bytes calldata compressed) external pure returns (UserOperation memory op) {
        op = abi.decode(LibZip.flzDecompress(compressed), (UserOperation));
    }

    function compressSimple(UserOperation memory op) external pure returns (bytes memory compressed) {
        compressed = LibZip.flzCompress(abi.encode(op));
    }

    function compress(UserOperation memory op) external view returns (bytes memory compressed) {
        // (1) selective pre-compression
        bytes memory preCompressedData = preCompress(op);

        // (2) general compression via FLZ
        compressed = LibZip.flzCompress(preCompressedData);
        return compressed;
    }

    function preCompress(UserOperation memory op) internal view returns (bytes memory preCompressed) {
        // initialize a dynamic bytes array for the pre-compressed data
        bytes memory buffer = new bytes(1024); // arbitrary initial size of 1024 bytes
        uint256 index = 0;

        // decode `callData` (selector, target, value, bytesOp)

        // 1. get selector (using _slice)
        bytes4 selector = bytes4(_slice(op.callData, 0, 4));

        // 2. copy callData (excluding selector) into a new bytes array
        bytes memory callData = new bytes(op.callData.length - 4);
        for (uint256 i = 0; i < callData.length; i++) {
            callData[i] = op.callData[i + 4];
        }

        // 3. decode callData
        // we skip value since we assume it's always 0
        (address target,, bytes memory bytesOp) = abi.decode(callData, (address, uint256, bytes));

        // encode boolean flags into the first byte of the buffer
        uint8 flags = 0;
        flags |= op.sender == target ? 0x01 : 0; // First bit for sender == target
        flags |= _isKintoContract(target) ? 0x02 : 0; // Second bit for Kinto contract
        flags |= (selector == IKintoWallet.execute.selector) ? 0x04 : 0; // Third bit for selector
        flags |= op.paymasterAndData.length > 0 ? 0x08 : 0; // Fourth bit for paymasterAndData
        // todo: we could add more flags here

        // add flags to buffer
        buffer[index] = bytes1(flags);
        index += 1;

        // encode sender
        bytes20 senderBytes = bytes20(op.sender);
        for (uint256 i = 0; i < 20; i++) {
            buffer[index + i] = senderBytes[i];
        }
        index += 20;

        // encode `nonce`
        index = _encodeUint256(op.nonce, buffer, index);

        // encode `initCode` (notice: we assume this is always empty for now)
        // index = _encodeBytes(op.initCode, buffer, index);

        // encode `calldata`:

        // 1. encode `target`

        // if sender and target are different, encode the target address
        // otherwise, we don't need to encode the target at all
        if (op.sender != target) {
            // if target is a Kinto contract, encode the Kinto contract name
            if (_isKintoContract(target)) {
                string memory name = kintoNames[target];
                bytes memory nameBytes = bytes(name);
                buffer[index] = bytes1(uint8(nameBytes.length));
                index += 1;
                for (uint256 i = 0; i < nameBytes.length; i++) {
                    buffer[index + i] = nameBytes[i];
                }
                index += nameBytes.length;
            } else {
                // if target is not a Kinto contract, encode the target address
                bytes20 targetBytes = bytes20(target);
                for (uint256 i = 0; i < 20; i++) {
                    buffer[index + i] = targetBytes[i];
                }
                index += 20;
            }
        }

        // (2) encode `value` (always 0 for now)
        // index = _encodeUint256(value, buffer, index);

        // (3) encode `bytesOp` length and content
        index = _encodeBytes(bytesOp, buffer, index);

        // callGasLimit
        index = _encodeUint256(op.callGasLimit, buffer, index);

        // verificationGasLimit
        index = _encodeUint256(op.verificationGasLimit, buffer, index);

        // preVerificationGas
        index = _encodeUint256(op.preVerificationGas, buffer, index);

        // maxFeePerGas
        index = _encodeUint256(op.maxFeePerGas, buffer, index);

        // maxPriorityFeePerGas
        index = _encodeUint256(op.maxPriorityFeePerGas, buffer, index);

        // encode `paymasterAndData` (notice: we assume always the same paymaster and no data for now)
        // index = _encodeBytes(op.paymasterAndData, buffer, index);

        // encode `signature` length and content
        index = _encodeBytes(op.signature, buffer, index);

        // adjust the size of the buffer to the actual data length
        preCompressed = new bytes(index);
        for (uint256 i = 0; i < index; i++) {
            preCompressed[i] = buffer[i];
        }
        return preCompressed;
    }

    /* ============ Auth methods ============ */

    function setKintoContract(string memory name, address target) external onlyOwner {
        kintoContracts[name] = target;
        kintoNames[target] = name;
        // emit event
        emit KintoContractSet(name, target);
    }

    /* ============ Utils ============ */

    function _isKintoContract(address target) internal view returns (bool) {
        if (keccak256(abi.encodePacked(kintoNames[target])) != keccak256("")) {
            return true;
        }
        return false;
    }

    /// @dev slice bytes arrays
    function _slice(bytes memory data, uint256 start, uint256 length) internal pure returns (bytes memory) {
        bytes memory part = new bytes(length);
        for (uint256 i = 0; i < length; i++) {
            part[i] = data[i + start];
        }
        return part;
    }

    function _bytesToAddress(bytes memory _bytes) internal pure returns (address addr) {
        assembly {
            addr := mload(add(_bytes, 20))
        }
    }

    function _bytesToUint256(bytes memory _bytes) internal pure returns (uint256 value) {
        assembly {
            value := mload(add(_bytes, 32))
        }
    }

    function _encodeUint256(uint256 value, bytes memory buffer, uint256 index)
        internal
        pure
        returns (uint256 newIndex)
    {
        for (uint256 i = 0; i < 32; i++) {
            // uint256 is 32 bytes
            buffer[index + i] = bytes1(uint8(value >> (8 * (31 - i))));
        }
        return index + 32; // Increase index by 32 bytes
    }

    function _encodeBytes(bytes memory data, bytes memory buffer, uint256 index)
        internal
        pure
        returns (uint256 newIndex)
    {
        // encode length of `data`
        newIndex = _encodeUint256(data.length, buffer, index);

        // encode contents of `data`
        for (uint256 i = 0; i < data.length; i++) {
            buffer[newIndex + i] = data[i];
        }

        return newIndex + data.length; // Increase index by the length of `data`
    }
}
