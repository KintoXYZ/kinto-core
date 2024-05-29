// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../interfaces/IOpInflator.sol";
import "../interfaces/IKintoWallet.sol";

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@solady/utils/LibZip.sol";

/// @notice Inflator contract for Kinto user operations
/// @dev This contract is responsible for inflating and compressing (off-chain) user operations
/// For further compression, consider: (1) using assembly for encoding/decoding, 
/// (2) hardcoding gas params (or using smaller types, same for nonce), (3) using IDs instead of names for Kinto contracts

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
contract KintoInflator is IOpInflator, OwnableUpgradeable, UUPSUpgradeable {
    mapping(string => address) public kintoContracts; // mapping of Kinto contract names to addresses
    mapping(address => string) public kintoNames; // mapping of Kinto contract addresses to names

    event KintoContractSet(string name, address target);

    /* ============ Constructor & Upgrades ============ */

    constructor() {
        _disableInitializers();
    }

    /// @dev Upgrade calling `upgradeTo()`
    function initialize() external initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();
        _transferOwnership(msg.sender);
    }

    /// @dev Authorize the upgrade. Only by an owner.
    /// @param newImplementation address of the new implementation
    function _authorizeUpgrade(address newImplementation) internal view override onlyOwner {
        (newImplementation);
    }

    /* ============ Inflate & Compress ============ */

    function inflate(bytes calldata compressed) external view returns (UserOperation memory op) {
        // decompress the data
        return this._inflate(LibZip.flzDecompress(compressed));
    }

    function _inflate(bytes calldata decompressed) public view returns (UserOperation memory op) {
        uint256 cursor = 0; // keep track of the current position in the decompressed data

        // extract flags
        uint8 flags = uint8(decompressed[cursor]);
        cursor += 1;

        // extract `sender`
        op.sender = address(uint160(bytes20(decompressed[cursor:cursor + 20])));
        cursor += 20;

        // extract `nonce`
        op.nonce = uint32(bytes4(decompressed[cursor:cursor + 4]));
        cursor += 4;

        // extract `initCode`
        uint32 initCodeLength = uint32(bytes4(decompressed[cursor:cursor + 4]));
        cursor += 4;
        op.initCode = _slice(decompressed, cursor, initCodeLength);
        cursor += initCodeLength;

        // Decode callData based on the selector (execute or executeBatch)
        bytes memory callData;
        if (flags & 0x01 == 0x01) {
            // if selector is `execute`, decode the callData as a single operation
            (cursor, callData) = _inflateExecuteCalldata(op.sender, flags, decompressed, cursor);
        } else {
            // if selector is `executeBatch`, decode the callData as a batch of operations
            (cursor, callData) = _inflateExecuteBatchCalldata(decompressed, cursor);
        }
        op.callData = callData;

        // extract gas parameters and other values using direct conversions
        op.callGasLimit = uint256(bytes32(decompressed[cursor:cursor + 32]));
        cursor += 32;

        op.verificationGasLimit = uint256(bytes32(decompressed[cursor:cursor + 32]));
        cursor += 32;

        op.preVerificationGas = uint32(bytes4(decompressed[cursor:cursor + 4]));
        cursor += 4;

        op.maxFeePerGas = uint48(bytes6(decompressed[cursor:cursor + 6]));
        cursor += 6;

        op.maxPriorityFeePerGas = uint48(bytes6(decompressed[cursor:cursor + 6]));
        cursor += 6;

        // Extract paymasterAndData if the flag is set
        if (flags & 0x02 == 0x02) {
            op.paymasterAndData = abi.encodePacked(kintoContracts["SP"]);
        }

        // Decode signature length and content
        uint32 signatureLength = uint32(bytes4(decompressed[cursor:cursor + 4]));
        cursor += 4;
        require(cursor + signatureLength <= decompressed.length, "Invalid signature length");
        op.signature = decompressed[cursor:cursor + signatureLength];

        return op;
    }

    function compress(UserOperation memory op) external view returns (bytes memory compressed) {
        // initialize a dynamic bytes array for the pre-compressed data
        bytes memory buffer = new bytes(1024); // arbitrary size of 1024 bytes (resized later)
        uint256 cursor = 0;

        // decode `callData` (selector, target, value, bytesOp)

        // decode selector and prepare callData
        bytes4 selector = bytes4(_slice(op.callData, 0, 4));
        bytes memory callData = _slice(op.callData, 4, op.callData.length - 4);

        // set flags based on conditions into buffer
        buffer[cursor] = bytes1(_flags(selector, op, callData));
        cursor += 1;

        // encode `sender`, `nonce` and `initCode`
        cursor = _encodeAddress(op.sender, buffer, cursor);
        cursor = _encodeUint32(op.nonce, buffer, cursor); // we assume `nonce` can't fits in 32 bits
        cursor = _encodeBytes(op.initCode, buffer, cursor);

        // encode `callData` depending on the selector
        if (selector == IKintoWallet.execute.selector) {
            // if selector is `execute`, encode the callData as a single operation
            (address target, uint256 value, bytes memory bytesOp) = abi.decode(callData, (address, uint256, bytes));
            cursor = _encodeExecuteCalldata(op, target, value, bytesOp, buffer, cursor);
        } else {
            // if selector is `executeBatch`, encode the callData as a batch of operations
            (address[] memory targets, uint256[] memory values, bytes[] memory bytesOps) = abi.decode(callData, (address[], uint256[], bytes[]));
            cursor = _encodeExecuteBatchCalldata(targets, values, bytesOps, buffer, cursor);
        }

        // encode gas params: `callGasLimit`, `verificationGasLimit`, `preVerificationGas`, `maxFeePerGas`, `maxPriorityFeePerGas`
        cursor = _encodeUint256(op.callGasLimit, buffer, cursor);
        cursor = _encodeUint256(op.verificationGasLimit, buffer, cursor);
        cursor = _encodeUint32(op.preVerificationGas, buffer, cursor);
        cursor = _encodeUint48(op.maxFeePerGas, buffer, cursor);
        cursor = _encodeUint48(op.maxPriorityFeePerGas, buffer, cursor);

        // encode `paymasterAndData` (we assume always the same paymaster so we don't need to encode it)
        // cursor = _encodeBytes(op.paymasterAndData, buffer, cursor);

        // encode `signature` content
        cursor = _encodeBytes(op.signature, buffer, cursor);

        // trim buffer size to the actual data length
        compressed = new bytes(cursor);
        for (uint256 i = 0; i < cursor; i++) {
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

    /* ============ Inflate Helpers ============ */

    /// @notice extracts `calldata` (selector, target, value, bytesOp)
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
                target = _bytesToAddress(data, cursor);
                cursor += 20;
            }
        }

        // 2. extract value
        uint256 value = _bytesToUint256(data, cursor);
        cursor += 32;

        // 3. extract bytesOp
        uint256 bytesOpLength = _bytesToUint32(data, cursor);
        cursor += 4;
        bytes memory bytesOp = _slice(data, cursor, bytesOpLength);
        cursor += bytesOpLength;

        // 4. build `callData`
        callData = abi.encodeCall(IKintoWallet.execute, (target, value, bytesOp));

        newCursor = cursor;
    }

    function _inflateExecuteBatchCalldata(bytes memory data, uint256 cursor)
        internal
        pure
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
            targets[i] = _bytesToAddress(data, cursor);
            cursor += 20;

            // extract value
            values[i] = _bytesToUint256(data, cursor);
            cursor += 32;

            // extract bytesOp
            uint256 bytesOpLength = _bytesToUint32(data, cursor);
            cursor += 4;
            bytesOps[i] = _slice(data, cursor, bytesOpLength);
            cursor += bytesOpLength;
        }

        //build `callData`
        callData = abi.encodeCall(IKintoWallet.executeBatch, (targets, values, bytesOps));

        newCursor = cursor;
    }

    /* ============ Compress Helpers ============ */

    function _flags(bytes4 selector, UserOperation memory op, bytes memory callData)
        internal
        view
        returns (uint8 flags)
    {
        // encode boolean flags into the first byte of the buffer
        flags |= (selector == IKintoWallet.execute.selector) ? 0x01 : 0; // first bit for selector
        flags |= op.paymasterAndData.length > 0 ? 0x02 : 0; // second bit for paymasterAndData

        if (selector == IKintoWallet.execute.selector) {
            // we skip value since we assume it's always 0
            (address target,,) = abi.decode(callData, (address, uint256, bytes));
            flags |= op.sender == target ? 0x04 : 0; // third bit for sender == target
            flags |= _isKintoContract(target) ? 0x08 : 0; // fourth bit for Kinto contract
        } else {
            (address[] memory targets,,) = abi.decode(callData, (address[], uint256[], bytes[]));
            // num ops
            uint256 numOps = targets.length;
            flags |= uint8(numOps << 1); // 2nd to 7th bits for number of operations in the batch
        }
    }

    function _encodeExecuteCalldata(
        UserOperation memory op,
        address target,
        uint256 value,
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

        // 2. encode `value`
        index = _encodeUint256(value, buffer, index);

        // 3. encode `bytesOp` length and content
        newIndex = _encodeBytes(bytesOp, buffer, index);
    }

    function _encodeExecuteBatchCalldata(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory bytesOps,
        bytes memory buffer,
        uint256 index
    ) internal pure returns (uint256 newIndex) {
        // encode number of operations in the batch
        buffer[index] = bytes1(uint8(targets.length));
        index += 1;

        // encode targets (as addresses, potentially we can improve this)
        for (uint8 i = 0; i < uint8(targets.length); i++) {
            index = _encodeAddress(targets[i], buffer, index);

            // encode value
            index = _encodeUint256(values[i], buffer, index);

            // encode bytesOps content
            index = _encodeBytes(bytesOps[i], buffer, index);
        }

        newIndex = index;
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

    function _bytesToAddress(bytes memory data, uint256 start) private pure returns (address addr) {
        require(data.length >= start + 20, "Data too short");
        assembly {
            addr := mload(add(add(data, 20), start))
        }
    }

    function _bytesToUint32(bytes memory _bytes, uint256 start) internal pure returns (uint32 value) {
        require(_bytes.length >= start + 4, "Data too short");
        assembly {
            value := mload(add(add(_bytes, 4), start))
        }
    }

    function _bytesToUint256(bytes memory _bytes, uint256 start) internal pure returns (uint256 value) {
        require(_bytes.length >= start + 32, "Data too short");
        assembly {
            value := mload(add(add(_bytes, 32), start))
        }
    }

    function _encodeUint32(uint256 value, bytes memory buffer, uint256 index)
        internal
        pure
        returns (uint256 newIndex)
    {
        for (uint256 i = 0; i < 4; i++) {
            buffer[index + i] = bytes1(uint8(value >> (8 * (3 - i))));
        }
        return index + 4; // increase index by 4 bytes
    }

    function _encodeUint48(uint256 value, bytes memory buffer, uint256 index)
        internal
        pure
        returns (uint256 newIndex)
    {
        for (uint256 i = 0; i < 6; i++) {
            buffer[index + i] = bytes1(uint8(value >> (8 * (5 - i))));
        }
        return index + 6; // increase index by 6 bytes
    }

    function _encodeUint256(uint256 value, bytes memory buffer, uint256 index)
        internal
        pure
        returns (uint256 newIndex)
    {
        for (uint256 i = 0; i < 32; i++) {
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
