// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8;

import "../interfaces/IInflator.sol";

/**
 * note: forked from https://github.com/daimo-eth/bulk/blob/master/src/BundleBulker.sol
 * only replaces ENTRY_POINT address with an immutable variable
 *
 * Reinflates a compressed, inflatord 4337 bundle, then submits to EntryPoint.
 *
 * Lets anyone register a new inflator.
 */
contract BundleBulker {
    IEntryPoint public immutable entryPoint;

    mapping(uint32 => IInflator) public idToInflator;
    mapping(IInflator => uint32) public inflatorToID;

    event InflatorRegistered(uint32 id, IInflator inflator);

    constructor(IEntryPoint _entryPoint) {
        require(address(_entryPoint) != address(0), "Entry point cannot be 0");
        entryPoint = _entryPoint;
    }

    function registerInflator(uint32 inflatorId, IInflator inflator) public {
        require(inflatorId != 0, "Inflator ID cannot be 0");
        require(
            bytes4(inflatorId) != this.registerInflator.selector && bytes4(inflatorId) != this.inflate.selector,
            "Inflator ID cannot clash with other functions"
        );
        require(address(inflator) != address(0), "Inflator address cannot be 0");
        require(address(idToInflator[inflatorId]) == address(0), "Inflator already registered");
        require(inflatorToID[inflator] == 0, "Inflator already registered");

        idToInflator[inflatorId] = inflator;
        inflatorToID[inflator] = inflatorId;

        emit InflatorRegistered(inflatorId, inflator);
    }

    function inflate(bytes calldata compressed)
        public
        view
        returns (UserOperation[] memory ops, address payable beneficiary)
    {
        uint32 inflatorID = uint32(bytes4(compressed[0:4]));
        IInflator inflator = idToInflator[inflatorID];
        require(address(inflator) != address(0), "Inflator not registered");
        return inflator.inflate(compressed[4:]);
    }

    fallback() external {
        (UserOperation[] memory ops, address payable beneficiary) = inflate(msg.data);
        IEntryPoint(entryPoint).handleOps(ops, beneficiary);
    }
}
