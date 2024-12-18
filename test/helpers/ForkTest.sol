// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {BaseTest} from "@kinto-core-test/helpers/BaseTest.sol";

abstract contract ForkTest is BaseTest {
    function setUp() public virtual override {
        super.setUp();

        // deploy chain contracts and pick a chain to use
        setUpChain();

        // label commonly used addresses for better stacktraces
        labelAddresses();
    }

    function setUpChain() public virtual {}
    function labelAddresses() public virtual {}

    function setUpEthereumFork() public {
        string memory rpc = vm.envString("ETHEREUM_RPC_URL");
        require(bytes(rpc).length > 0, "ETHEREUM_RPC_URL is not set");

        vm.createSelectFork(rpc);
    }

    function setUpArbitrumFork() public {
        string memory rpc = vm.envString("ARBITRUM_RPC_URL");
        require(bytes(rpc).length > 0, "ARBITRUM_RPC_URL is not set");

        vm.createSelectFork(rpc);
    }
}
