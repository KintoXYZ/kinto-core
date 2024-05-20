// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import "@kinto-core/interfaces/bridger/IBridger.sol";
import "@kinto-core/bridger/BridgerL2.sol";

import "@kinto-core-test/helpers/UUPSProxy.sol";
import "@kinto-core-test/helpers/SignatureHelper.sol";
import "@kinto-core-test/helpers/SignatureHelper.sol";
import "@kinto-core-test/SharedSetup.t.sol";

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract BridgerL2Test is SignatureHelper, SharedSetup {
    function setUp() public override {
        super.setUp();
        // transfer owner's ownership to _owner
        vm.prank(_bridgerL2.owner());
        _bridgerL2.transferOwnership(_owner);

        // upgrade Bridger L2 to latest version
        // TODO: remove upgrade after having actually upgraded the contract on mainnet
        BridgerL2 _newImpl = new BridgerL2(address(_walletFactory));
        vm.prank(_owner);
        _bridgerL2.upgradeTo(address(_newImpl));

        fundSponsorForApp(_owner, address(_bridgerL2));
        registerApp(_owner, "bridger", address(_bridgerL2));
    }

    function setUpChain() public virtual override {
        setUpKintoFork();
    }

    /* ============ Claim Commitment (with real asset) ============ */

    function testClaimCommitment_WhenRealAsset() public {
        // UI "wrong" assets
        address[] memory UI_assets = new address[](4);
        UI_assets[0] = 0x4190A8ABDe37c9A85fAC181037844615BA934711; // sDAI
        UI_assets[1] = 0xF4d81A46cc3fCA44f88d87912A35E7fCC4B398ee; // sUSDe
        UI_assets[2] = 0x6e316425A25D2Cf15fb04BCD3eE7c6325B240200; // wstETH
        UI_assets[3] = 0xC60F14d95B87417BfD17a376276DE15bE7171d31; // weETH

        // L2 representations
        address[] memory L2_assets = new address[](4);
        L2_assets[0] = 0x5da1004F7341D510C6651C67B4EFcEEA76Cac0E8; // sDAI
        L2_assets[1] = 0x505de0f7a5d786063348aB5BC31e3a21344fA7B0; // sUSDe
        L2_assets[2] = 0x057e70cCa0dC435786a50FcF440bf8FcC1eEAf17; // wstETH
        L2_assets[3] = 0x0Ee700095AeDFe0814fFf7d6DFD75461De8e2b19; // weETH

        for (uint256 i = 0; i < 4; i++) {
            address _asset = UI_assets[i];
            uint256 _amount = 100;

            address[] memory _assets = new address[](1);
            _assets[0] = _asset;

            vm.startPrank(_owner);

            _bridgerL2.setDepositedAssets(_assets);
            _bridgerL2.writeL2Deposit(address(_kintoWallet), _asset, _amount);
            _bridgerL2.unlockCommitments();

            vm.stopPrank();

            // add balance of the real asset representation to the bridger
            deal(L2_assets[i], address(_bridgerL2), _amount);

            vm.prank(address(_kintoWallet));
            _bridgerL2.claimCommitment();

            assertEq(_bridgerL2.deposits(address(_kintoWallet), _asset), 0);
            assertEq(ERC20(L2_assets[i]).balanceOf(address(_kintoWallet)), _amount);
        }
    }
}
