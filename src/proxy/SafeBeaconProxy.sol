// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

/**
 * @title GardenFactory
 * @author Babylon Finance
 *
 * Factory to create garden contracts
 */
contract SafeBeaconProxy is BeaconProxy {
    /**
     * @dev Initializes the proxy with `beacon`.
     *
     * If `data` is nonempty, it's used as data in a delegate call to the implementation returned by the beacon. This
     * will typically be an encoded function call, and allows initializing the storage of the proxy like a Solidity
     * constructor.
     *
     * Requirements:
     *
     * - `beacon` must be a contract with the interface {IBeacon}.
     */
    constructor(address beacon, bytes memory data) payable BeaconProxy(beacon, data) {}

    /**
     * @dev Accepts all ETH transfers but does not proxy calls to the implementation.
     *
     * Due to EIP-2929 the proxy overhead gas cost is higher than 2300 gas which is the stipend used by address.transfer.
     * This results to a `out of gas` error for proxy calls initiated by code `address.transfer`.
     * A notable example is WETH https://etherscan.io/address/0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2#code
     * A downside of this approach is that a proxy implementation contract can not handle receiving pure ETH.
     * In a scope of Babylon project this is acceptable but should be kept in mind at all times.
     *
     */
    receive() external payable override {}
}
