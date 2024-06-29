// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {stdJson} from "forge-std/StdJson.sol";

import {UUPSProxy} from "@kinto-core-test/helpers/UUPSProxy.sol";
import {SignatureHelper} from "@kinto-core-test/helpers/SignatureHelper.sol";
import {ArtifactsReader} from "@kinto-core-test/helpers/ArtifactsReader.sol";
import {ForkTest} from "@kinto-core-test/helpers/ForkTest.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {MiningAdaptor} from "@kinto-core/liquidity-mining/MiningAdaptor.sol";
import {KintoToken} from "@kinto-core/tokens/KintoToken.sol";

import "forge-std/console2.sol";

contract MiningAdaptorTest is SignatureHelper, ForkTest, ArtifactsReader {
    using stdJson for string;

    MiningAdaptor internal miningAdaptor;

    function setUp() public override {
        super.setUp();

        miningAdaptor = new MiningAdaptor();
    }

    function setUpChain() public virtual override {
        setUpEthereumFork();
    }

    function testBridge() public {
        KintoToken kintoToken = KintoToken(miningAdaptor.KINTO());

        // set mining contract
        vm.prank(kintoToken.owner());
        kintoToken.setMiningContract(address(miningAdaptor));

        uint256 vaultBalanceBefore = kintoToken.balanceOf(miningAdaptor.VAULT());

        // deal some K to mining contract
        deal(miningAdaptor.KINTO(), address(miningAdaptor), 1e18);

        // bridge to Kinto chain
        miningAdaptor.bridge{value: 0.01 ether}();

        assertEq(kintoToken.balanceOf(miningAdaptor.VAULT()) - vaultBalanceBefore, 1e18);
    }
}
