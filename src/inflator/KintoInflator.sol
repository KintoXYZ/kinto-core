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

/// On the first byte of the compressed data we store some flags.
/// The first bit is used to encode whether the selector is `execute` or `executeBatch` (so we don't need to encode the selector)
/// 0x01: selector

/// If it is an `execute`, we use the following 4 bits to as follows:
/// 0x02: paymasterAndData (whether to use the SponsorPaymaster or not) so we don't need to encode the paymaster address
/// 0x04: sender == target (whether the sender is the same as the target) so we don't need to encode the target
/// 0x08: Kinto contract (whether the target is a Kinto contract) so we can use the contract name instead of the address

/// If it is an `executeBatch`, we use the following bits to encode the number of operations in the batch (max supported will be 128)
/// 0x02: paymasterAndData (whether to use the SponsorPaymaster or not) so we don't need to encode the paymaster address. We assume that paymaster is always the SponsorPaymaster.
/// 0x04 .. 0x80: number of operations in the batch

/// The rest of the flags are not used.
/// All other UserOperation fields are encoded as is.
contract KintoInflator is IOpInflator, Ownable {
    mapping(string => address) public kintoContracts; // mapping of Kinto contract names to addresses
    mapping(address => string) public kintoNames; // mapping of Kinto contract addresses to names

    event KintoContractSet(string name, address target);

    function inflate(bytes calldata compressed) external view returns (UserOperation memory op) {
        // decompress the data
        bytes memory decompressed = LibZip.flzDecompress(compressed);
        uint256 cursor = 0; // keep track of the current position in the decompressed data

        // extract flags
        uint8 flags = uint8(decompressed[cursor]);
        cursor += 1;

        // extract `sender`
        op.sender = _bytesToAddress(_slice(decompressed, cursor, 20));
        cursor += 20;

        // extract `nonce`
        op.nonce = _bytesToUint256(_slice(decompressed, cursor, 32));
        cursor += 32;

        // extract `initCode` (notice: we are always using an empty initCode for now)
        // op.initCode = bytes("");

        // read first flag to check whether selector is `execute` or `executeBatch`
        // and inflate `callData` accordingly
        bytes memory callData;
        if (flags & 0x01 == 0x01) {
            // if selector is `execute`, we decode the callData as a single operation
            (cursor, callData) = _inflateExecuteCalldata(op.sender, flags, decompressed, cursor);
        } else {
            // if selector is `executeBatch`, we decode the callData as a batch of operations
            (cursor, callData) = _inflateExecuteBatchCalldata(op.sender, flags, decompressed, cursor);
        }
        op.callData = callData;

        // extract `callGasLimit`
        op.callGasLimit = _bytesToUint256(_slice(decompressed, cursor, 32));
        cursor += 32;

        // extract `verificationGasLimit`
        op.verificationGasLimit = _bytesToUint256(_slice(decompressed, cursor, 32));
        cursor += 32;

        // extract `preVerificationGas`
        op.preVerificationGas = _bytesToUint256(_slice(decompressed, cursor, 32));
        cursor += 32;

        // extract `maxFeePerGas`
        op.maxFeePerGas = _bytesToUint256(_slice(decompressed, cursor, 32));
        cursor += 32;

        // extract `maxPriorityFeePerGas`
        op.maxPriorityFeePerGas = _bytesToUint256(_slice(decompressed, cursor, 32));
        cursor += 32;

        // extract `paymasterAndData`
        // if second flag is set, it means paymasterAndData is set so we can use the contract stored in the mapping
        if (flags & 0x02 == 0x02) {
            op.paymasterAndData = abi.encodePacked(kintoContracts["SP"]);
        }

        // decode signature
        uint256 signatureLength = _bytesToUint32(_slice(decompressed, cursor, 4));
        cursor += 4;
        op.signature = _slice(decompressed, cursor, signatureLength);
        cursor += signatureLength;

        return op;
    }

    function compress(UserOperation memory op) external view returns (bytes memory compressed) {
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
        // encode boolean flags into the first byte of the buffer
        uint8 flags = 0;
        flags |= (selector == IKintoWallet.execute.selector) ? 0x01 : 0; // first bit for selector
        flags |= op.paymasterAndData.length > 0 ? 0x02 : 0; // second bit for paymasterAndData

        if (selector == IKintoWallet.execute.selector) {
            // we skip value since we assume it's always 0
            (address target,, bytes memory bytesOp) = abi.decode(callData, (address, uint256, bytes));
            flags |= op.sender == target ? 0x04 : 0; // third bit for sender == target
            flags |= _isKintoContract(target) ? 0x08 : 0; // fourth bit for Kinto contract
                // todo: we could add more flags here
        } else {
            (address[] memory targets,,) = abi.decode(callData, (address[], uint256[], bytes[]));
            // num ops
            uint256 numOps = targets.length;
            flags |= uint8(numOps << 1); // 2nd to 7th bits for number of operations in the batch
        }

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

        // encode `initCode`
        // (we assume always an empty initCode so we don't need to encode it)
        // index = _encodeBytes(op.initCode, buffer, index);

        // encode `callData` depending on the selector
        if (selector == IKintoWallet.execute.selector) {
            (address target,, bytes memory bytesOp) = abi.decode(callData, (address, uint256, bytes));
            // if selector is `execute`, encode the callData as a single operation
            index = _encodeExecuteCalldata(op, target, bytesOp, buffer, index);
        } else {
            (address[] memory targets,, bytes[] memory bytesOps) = abi.decode(callData, (address[], uint256[], bytes[]));
            // if selector is `executeBatch`, encode the callData as a batch of operations
            index = _encodeExecuteBatchCalldata(op, targets, bytesOps, buffer, index);
        }

        // encode `callGasLimit`
        index = _encodeUint256(op.callGasLimit, buffer, index);

        // encode `verificationGasLimit`
        index = _encodeUint256(op.verificationGasLimit, buffer, index);

        // encode `preVerificationGas`
        index = _encodeUint256(op.preVerificationGas, buffer, index);

        // encode `maxFeePerGas`
        index = _encodeUint256(op.maxFeePerGas, buffer, index);

        // encode `maxPriorityFeePerGas`
        index = _encodeUint256(op.maxPriorityFeePerGas, buffer, index);

        // encode `paymasterAndData`
        // (we assume always the same paymaster so we don't need to encode it)
        // index = _encodeBytes(op.paymasterAndData, buffer, index);

        // encode `signature` length and content
        index = _encodeBytes(op.signature, buffer, index);

        // adjust the size of the buffer to the actual data length
        compressed = new bytes(index);
        for (uint256 i = 0; i < index; i++) {
            compressed[i] = buffer[i];
        }

        return LibZip.flzCompress(compressed);
    }

    /* ============ Simple compress/inflate ============ */

    function inflateSimple(bytes calldata compressed) external pure returns (UserOperation memory op) {
        op = abi.decode(LibZip.flzDecompress(compressed), (UserOperation));
    }

    function compressSimple(UserOperation memory op) external pure returns (bytes memory compressed) {
        compressed = LibZip.flzCompress(abi.encode(op));
    }

    /* ============ Auth methods ============ */

    function setKintoContract(string memory name, address target) external onlyOwner {
        kintoContracts[name] = target;
        kintoNames[target] = name;
        // emit event
        emit KintoContractSet(name, target);
    }

    /* ============ Compress Helpers ============ */

    function _encodeExecuteCalldata(
        UserOperation memory op,
        address target,
        bytes memory bytesOp,
        bytes memory buffer,
        uint256 index
    ) internal view returns (uint256 newIndex) {
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
                index = _encodeAddress(target, buffer, index);
            }
        }

        // 2. encode `value` (always 0 for now)
        // index = _encodeUint256(value, buffer, index);

        // 3. encode `bytesOp` length and content
        newIndex = _encodeBytes(bytesOp, buffer, index);
    }

    function _encodeExecuteBatchCalldata(
        UserOperation memory op,
        address[] memory targets,
        bytes[] memory bytesOps,
        bytes memory buffer,
        uint256 index
    ) internal view returns (uint256 newIndex) {
        // encode number of operations in the batch
        buffer[index] = bytes1(uint8(targets.length));
        index += 1;

        // encode targets (as addresses, potentially we can improve this)
        for (uint8 i = 0; i < uint8(targets.length); i++) {
            index = _encodeAddress(targets[i], buffer, index);

            // encode bytesOps content
            index = _encodeBytes(bytesOps[i], buffer, index);
        }

        newIndex = index;
    }

    /* ============ Inflate Helpers ============ */

    /// @notice extracts `calldata` (selector, target, value, bytesOp)
    /// @dev skips `value` since we assume it's always 0
    function _inflateExecuteCalldata(address sender, uint8 flags, bytes memory data, uint256 cursor)
        internal
        view
        returns (uint256 newCursor, bytes memory callData)
    {
        // 1. extract target
        address target;

        // if fourth flag is set, it means target is a Kinto contract
        if (flags & 0x08 == 0x08) {
            uint8 nameLength = uint8(data[cursor]);
            cursor += 1;
            string memory name = string(_slice(data, cursor, nameLength));
            cursor += nameLength;

            // get contract address from mapping
            target = kintoContracts[name];
        } else {
            // if third flag is set, it means target == sender
            if (flags & 0x04 == 0x04) {
                target = sender;
            } else {
                // if target is not a Kinto contract, just extract target address
                target = _bytesToAddress(_slice(data, cursor, 20));
                cursor += 20;
            }
        }

        // 2. extract bytesOp
        uint256 bytesOpLength = _bytesToUint32(_slice(data, cursor, 4));
        cursor += 4;
        bytes memory bytesOp = _slice(data, cursor, bytesOpLength);
        cursor += bytesOpLength;

        // 3. build `callData`
        callData = abi.encodeCall(IKintoWallet.execute, (target, 0, bytesOp));

        newCursor = cursor;
    }

    function _inflateExecuteBatchCalldata(address sender, uint8 flags, bytes memory data, uint256 cursor)
        internal
        view
        returns (uint256 newCursor, bytes memory callData)
    {
        // extract number of operations in the batch
        uint8 numOps = uint8(data[cursor]);
        cursor += 1;

        address[] memory targets = new address[](numOps);
        uint256[] memory values = new uint256[](numOps);
        bytes[] memory bytesOps = new bytes[](numOps);

        // extract targets, values, and bytesOps
        for (uint8 i = 0; i < numOps; i++) {
            // extract target
            targets[i] = _bytesToAddress(_slice(data, cursor, 20));
            cursor += 20;

            // extract value (we assume this is always 0 for now)
            values[i] = 0;

            // extract bytesOp
            uint256 bytesOpLength = _bytesToUint32(_slice(data, cursor, 4));
            cursor += 4;
            bytesOps[i] = _slice(data, cursor, bytesOpLength);
            cursor += bytesOpLength;
        }

        //build `callData`
        callData = abi.encodeCall(IKintoWallet.executeBatch, (targets, values, bytesOps));

        newCursor = cursor;
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

    function _bytesToUint32(bytes memory _bytes) internal pure returns (uint32 value) {
        assembly {
            value := mload(add(_bytes, 4))
        }
    }

    function _encodeUint32(uint256 value, bytes memory buffer, uint256 index)
        internal
        pure
        returns (uint256 newIndex)
    {
        for (uint256 i = 0; i < 4; i++) {
            // uint32 is 4 bytes
            buffer[index + i] = bytes1(uint8(value >> (8 * (3 - i))));
        }
        return index + 4; // increase index by 4 bytes
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
        return index + 32; // increase index by 32 bytes
    }

    function _encodeBytes(bytes memory data, bytes memory buffer, uint256 index)
        internal
        pure
        returns (uint256 newIndex)
    {
        // encode length of `data` (we assume uint32 is more than enough for the length)
        newIndex = _encodeUint32(data.length, buffer, index);

        // encode contents of `data`
        for (uint256 i = 0; i < data.length; i++) {
            buffer[newIndex + i] = data[i];
        }

        return newIndex + data.length; // increase index by the length of `data`
    }

    function _encodeAddress(address addr, bytes memory buffer, uint256 index)
        internal
        pure
        returns (uint256 newIndex)
    {
        bytes20 addrBytes = bytes20(addr);
        for (uint256 i = 0; i < 20; i++) {
            buffer[index + i] = addrBytes[i];
        }
        return index + 20;
    }
}
