// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../../src/interfaces/IBridger.sol";
import "../../src/bridger/Bridger.sol";

import "../helpers/UUPSProxy.sol";
import "../helpers/TestSignature.sol";
import "../helpers/TestSignature.sol";
import "../harness/BridgerHarness.sol";
import "../SharedSetup.t.sol";

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

contract BridgerNewUpgrade is Bridger {
    function newFunction() external pure returns (uint256) {
        return 1;
    }

    constructor(address l2Vault) Bridger(l2Vault) {}
}

contract ERC20PermitToken is ERC20, ERC20Permit {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) ERC20Permit(name) {}
}

contract BridgerTest is TestSignature, SharedSetup {
    address constant l1ToL2Router = 0xD9041DeCaDcBA88844b373e7053B4AC7A3390D60;
    address constant kintoWalletL2 = address(33);
    address constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant UNI = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984;
    address constant STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address constant senderAccount = address(100);
    address constant l2Vault = address(99);

    BridgerHarness internal bridger;

    function setUp() public override {
        super.setUp();
        if (fork) {
            string memory rpc = vm.envString("ETHEREUM_RPC_URL");
            require(bytes(rpc).length > 0, "ETHEREUM_RPC_URL is not set");

            vm.chainId(1);
            mainnetFork = vm.createFork(rpc);
            vm.selectFork(mainnetFork);
            assertEq(vm.activeFork(), mainnetFork);

            bridger = BridgerHarness(payable(_getChainDeployment("Bridger")));

            // transfer owner's ownership to _owner
            vm.prank(bridger.owner());
            bridger.transferOwnership(_owner);
        } else {
            // deploy a new Bridger contract
            _deployBridger();

            // if running local tests, we want to replace some hardcoded addresses that the bridger uses
            // with mocked contracts
            ERC20PermitToken sDAI = new ERC20PermitToken("sDAI", "sDAI");
            vm.etch(bridger.sDAI(), address(sDAI).code); // add sDAI code to sDAI address in Bridger
        }
    }

    function testUp() public override {
        if (fork) return;
        assertEq(bridger.depositCount(), 0);
        assertEq(bridger.owner(), address(_owner));
        assertEq(bridger.swapsEnabled(), false);
        assertEq(bridger.senderAccount(), senderAccount);
        assertEq(bridger.l2Vault(), l2Vault);
    }

    function _deployBridger() internal {
        BridgerHarness implementation = new BridgerHarness(l2Vault);
        address proxy = address(new UUPSProxy{salt: 0}(address(implementation), ""));
        bridger = BridgerHarness(payable(proxy));

        vm.prank(_owner);
        bridger.initialize(senderAccount);
    }

    /* ============ Upgrade ============ */

    function testUpgradeTo() public {
        BridgerNewUpgrade _newImpl = new BridgerNewUpgrade(l2Vault);
        vm.prank(_owner);
        bridger.upgradeTo(address(_newImpl));
        assertEq(BridgerNewUpgrade(payable(address(bridger))).newFunction(), 1);
    }

    function testUpgradeTo_RevertWhen_CallerIsNotOwner() public {
        BridgerNewUpgrade _newImpl = new BridgerNewUpgrade(l2Vault);
        vm.expectRevert("Ownable: caller is not the owner");
        bridger.upgradeToAndCall(address(_newImpl), bytes(""));
    }

    /* ============ Bridger Deposit ============ */

    // deposit sDAI (no swap)
    function testDepositBySig_sDAI_WhenNoSwap() public {
        address assetToDeposit = bridger.sDAI();
        uint256 amountToDeposit = 1e18;
        uint256 balanceBefore = ERC20(assetToDeposit).balanceOf(address(bridger));
        uint256 depositBefore = bridger.deposits(_user, assetToDeposit);
        deal(assetToDeposit, _user, amountToDeposit);
        assertEq(ERC20(assetToDeposit).balanceOf(_user), amountToDeposit);

        IBridger.SwapData memory swapData = IBridger.SwapData(address(1), address(1), bytes(""), 0.1 ether);
        IBridger.SignatureData memory sigdata = _auxCreateBridgeSignature(
            kintoWalletL2,
            bridger,
            _user,
            assetToDeposit,
            assetToDeposit,
            amountToDeposit,
            amountToDeposit,
            _userPk,
            block.timestamp + 1000
        );
        bytes memory permitSignature = _auxCreatePermitSignature(
            IBridger.Permit(
                _user,
                address(bridger),
                amountToDeposit,
                ERC20Permit(assetToDeposit).nonces(_user),
                block.timestamp + 1000
            ),
            _userPk,
            ERC20Permit(assetToDeposit)
        );

        uint256 nonce = bridger.nonces(_user);
        vm.prank(_owner);
        bridger.depositBySig(permitSignature, sigdata, swapData);
        assertEq(bridger.nonces(_user), nonce + 1);
        assertEq(bridger.deposits(_user, assetToDeposit), depositBefore + amountToDeposit);
        assertEq(ERC20(assetToDeposit).balanceOf(address(bridger)), balanceBefore + amountToDeposit);
    }

    // deposit wstETH (no swap)
    function testDepositBySig_wstETH_WhenNoSwap() public {
        if (!fork) return;
        address assetToDeposit = bridger.wstETH();
        uint256 amountToDeposit = 1e18;
        uint256 balanceBefore = ERC20(assetToDeposit).balanceOf(address(bridger));
        uint256 depositBefore = bridger.deposits(_user, assetToDeposit);
        deal(assetToDeposit, _user, amountToDeposit);
        assertEq(ERC20(assetToDeposit).balanceOf(_user), amountToDeposit);

        IBridger.SwapData memory swapData = IBridger.SwapData(address(1), address(1), bytes(""), 0.1 ether);
        IBridger.SignatureData memory sigdata = _auxCreateBridgeSignature(
            kintoWalletL2,
            bridger,
            _user,
            assetToDeposit,
            assetToDeposit,
            amountToDeposit,
            amountToDeposit,
            _userPk,
            block.timestamp + 1000
        );
        bytes memory permitSignature = _auxCreatePermitSignature(
            IBridger.Permit(
                _user,
                address(bridger),
                amountToDeposit,
                ERC20Permit(assetToDeposit).nonces(_user),
                block.timestamp + 1000
            ),
            _userPk,
            ERC20Permit(assetToDeposit)
        );

        uint256 nonce = bridger.nonces(_user);
        vm.prank(_owner);
        bridger.depositBySig(permitSignature, sigdata, swapData);
        assertEq(bridger.nonces(_user), nonce + 1);
        assertEq(bridger.deposits(_user, assetToDeposit), depositBefore + amountToDeposit);
        assertEq(ERC20(assetToDeposit).balanceOf(address(bridger)), balanceBefore + amountToDeposit);
    }

    // deposit weETH (no swap)
    function testDepositBySig_weETH_WhenNoSwap() public {
        if (!fork) return;
        address assetToDeposit = bridger.weETH();
        uint256 amountToDeposit = 1e18;
        uint256 balanceBefore = ERC20(assetToDeposit).balanceOf(address(bridger));
        uint256 depositBefore = bridger.deposits(_user, assetToDeposit);
        deal(assetToDeposit, _user, amountToDeposit);
        assertEq(ERC20(assetToDeposit).balanceOf(_user), amountToDeposit);

        IBridger.SwapData memory swapData = IBridger.SwapData(address(1), address(1), bytes(""), 0.1 ether);
        IBridger.SignatureData memory sigdata = _auxCreateBridgeSignature(
            kintoWalletL2,
            bridger,
            _user,
            assetToDeposit,
            assetToDeposit,
            amountToDeposit,
            amountToDeposit,
            _userPk,
            block.timestamp + 1000
        );
        bytes memory permitSignature = _auxCreatePermitSignature(
            IBridger.Permit(
                _user,
                address(bridger),
                amountToDeposit,
                ERC20Permit(assetToDeposit).nonces(_user),
                block.timestamp + 1000
            ),
            _userPk,
            ERC20Permit(assetToDeposit)
        );

        uint256 nonce = bridger.nonces(_user);
        vm.prank(_owner);
        bridger.depositBySig(permitSignature, sigdata, swapData);
        assertEq(bridger.nonces(_user), nonce + 1);
        assertEq(bridger.deposits(_user, assetToDeposit), depositBefore + amountToDeposit);
        assertEq(ERC20(assetToDeposit).balanceOf(address(bridger)), balanceBefore + amountToDeposit);
    }

    // deposit sUSDe
    function testDepositBySig_sUSDe_WhenNoSwap() public {
        if (!fork) return;
        address assetToDeposit = bridger.sUSDe();
        uint256 amountToDeposit = 1e18;
        uint256 balanceBefore = ERC20(assetToDeposit).balanceOf(address(bridger));
        uint256 depositBefore = bridger.deposits(_user, assetToDeposit);
        deal(assetToDeposit, _user, amountToDeposit);
        assertEq(ERC20(assetToDeposit).balanceOf(_user), amountToDeposit);

        IBridger.SwapData memory swapData = IBridger.SwapData(address(1), address(1), bytes(""), 0.1 ether);
        IBridger.SignatureData memory sigdata = _auxCreateBridgeSignature(
            kintoWalletL2,
            bridger,
            _user,
            assetToDeposit,
            assetToDeposit,
            amountToDeposit,
            amountToDeposit,
            _userPk,
            block.timestamp + 1000
        );
        bytes memory permitSignature = _auxCreatePermitSignature(
            IBridger.Permit(
                _user,
                address(bridger),
                amountToDeposit,
                ERC20Permit(assetToDeposit).nonces(_user),
                block.timestamp + 1000
            ),
            _userPk,
            ERC20Permit(assetToDeposit)
        );

        uint256 nonce = bridger.nonces(_user);
        vm.prank(_owner);
        bridger.depositBySig(permitSignature, sigdata, swapData);
        assertEq(bridger.nonces(_user), nonce + 1);
        assertEq(bridger.deposits(_user, assetToDeposit), depositBefore + amountToDeposit);
        assertEq(ERC20(assetToDeposit).balanceOf(address(bridger)), balanceBefore + amountToDeposit);
    }

    // USDe to sUSDe
    function testDepositBySig_WhenUSDeTosUSDe() public {
        if (!fork) return;
        address assetToDeposit = bridger.USDe();
        uint256 amountToDeposit = 1e18;
        uint256 sharesBefore = ERC20(bridger.sUSDe()).balanceOf(address(bridger));
        deal(assetToDeposit, _user, amountToDeposit);
        assertEq(ERC20(assetToDeposit).balanceOf(_user), amountToDeposit);

        IBridger.SwapData memory swapData = IBridger.SwapData(address(1), address(1), bytes(""), 0);
        IBridger.SignatureData memory sigdata = _auxCreateBridgeSignature(
            kintoWalletL2,
            bridger,
            _user,
            assetToDeposit,
            bridger.sUSDe(),
            amountToDeposit,
            1e17,
            _userPk,
            block.timestamp + 1000
        );

        bytes memory permitSignature = _auxCreatePermitSignature(
            IBridger.Permit(
                _user,
                address(bridger),
                amountToDeposit,
                ERC20Permit(assetToDeposit).nonces(_user),
                block.timestamp + 1000
            ),
            _userPk,
            ERC20Permit(assetToDeposit)
        );

        uint256 nonce = bridger.nonces(_user);
        vm.prank(_owner);
        bridger.depositBySig(permitSignature, sigdata, swapData);
        assertEq(bridger.nonces(_user), nonce + 1);
        assertEq(bridger.deposits(_user, assetToDeposit), amountToDeposit);

        uint256 shares = ERC4626(bridger.sUSDe()).previewDeposit(amountToDeposit);
        assertEq(ERC20(bridger.sUSDe()).balanceOf(address(bridger)), sharesBefore + shares);
    }

    // USDe to sDAI
    function testDepositBySig_WhenUSDeTosDAI() public {
        if (!fork) return;

        vm.rollFork(19418477); // block number in which the 0x API data was fetched
        _deployBridger(); // re-deploy the bridger on block

        vm.deal(_owner, 1e18);

        // enable swaps
        vm.prank(_owner);
        bridger.setSwapsEnabled(true);

        // whitelist USDe as inputAsset
        address[] memory assets = new address[](1);
        assets[0] = bridger.USDe();
        bool[] memory flags = new bool[](1);
        flags[0] = true;
        vm.prank(_owner);
        bridger.whitelistAssets(assets, flags);

        // top-up _user USDe balance
        address assetToDeposit = bridger.USDe();
        uint256 amountToDeposit = 1e18;
        deal(assetToDeposit, _user, amountToDeposit);

        // create a permit signature to allow the bridger to transfer the user's UNI
        bytes memory permitSignature = _auxCreatePermitSignature(
            IBridger.Permit(
                _user,
                address(bridger),
                amountToDeposit,
                ERC20Permit(assetToDeposit).nonces(_user),
                block.timestamp + 1000
            ),
            _userPk,
            ERC20Permit(assetToDeposit)
        );

        // 100 USDe to sDAI quote's swapData
        // https://api.0x.org/swap/v1/quote?sellToken=0x4c9EDD5852cd905f086C759E8383e09bff1E68B3&buyToken=0x83F20F44975D03b1b09e64809B757c47f942BEeA&sellAmount=10000000000000000
        bytes memory data =
            hex"0f3b31b2000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000de0b6b3a76400000000000000000000000000000000000000000000000000000d317016cdaaa58700000000000000000000000000000000000000000000000000000000000000030000000000000000000000004c9edd5852cd905f086c759e8383e09bff1e68b3000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc200000000000000000000000083f20f44975d03b1b09e64809b757c47f942beea0000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000424c9edd5852cd905f086c759e8383e09bff1e68b3000064dac17f958d2ee523a2206206994597c13d831ec70001f4c02aaa39b223fe8d0a0e5c4f27ead9083c756cc200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000002bc02aaa39b223fe8d0a0e5c4f27ead9083c756cc20001f483f20f44975d03b1b09e64809b757c47f942beea000000000000000000000000000000000000000000869584cd0000000000000000000000001000000000000000000000000000000000000011000000000000000000000000000000005e39828abf45b7271af8ffd8c3fa0f40";
        address swapTarget = 0xDef1C0ded9bec7F1a1670819833240f027b25EfF;
        IBridger.SwapData memory swapData = IBridger.SwapData(swapTarget, swapTarget, data, 0); // spender, swapTarget, swapCallData, gasFee

        // create a bridge signature to allow the bridger to deposit the user's UNI
        IBridger.SignatureData memory sigdata = _auxCreateBridgeSignature(
            kintoWalletL2,
            bridger,
            _user,
            assetToDeposit,
            bridger.sDAI(),
            amountToDeposit,
            950664239593989504,
            _userPk,
            block.timestamp + 1000
        );
        uint256 nonce = bridger.nonces(_user);

        vm.prank(_owner);
        bridger.depositBySig{value: 0}(permitSignature, sigdata, swapData);

        assertEq(bridger.nonces(_user), nonce + 1);
        assertEq(bridger.deposits(_user, assetToDeposit), 1e18);
        assertEq(ERC20(assetToDeposit).balanceOf(address(bridger)), 0); // there's no USDe since it was swapped
        assertGe(ERC20(bridger.sDAI()).balanceOf(address(bridger)), 950664239593989504); // sDAI balance should be equal or greater than the min guaranteed
            // assertApproxEqRel(ERC20(bridger.sDAI()).balanceOf(address(bridger)), 950664239593989504, 0.015e18); // 1.5%
    }

    // UNI to sUSDe
    function testDepositBySig_WhenSwap_WhenUNITosUSDe() public {
        if (!fork) return;

        vm.rollFork(19412323); // block number in which the 0x API data was fetched
        _deployBridger(); // re-deploy the bridger on block

        // enable swaps
        vm.prank(_owner);
        bridger.setSwapsEnabled(true);

        // whitelist UNI as inputAsset
        address[] memory assets = new address[](1);
        assets[0] = UNI;
        bool[] memory flags = new bool[](1);
        flags[0] = true;
        vm.prank(_owner);
        bridger.whitelistAssets(assets, flags);

        // top-up _user UNI balance
        address assetToDeposit = UNI;
        uint256 amountToDeposit = 1e18;
        deal(assetToDeposit, _user, amountToDeposit);

        // create a permit signature to allow the bridger to transfer the user's UNI
        bytes memory permitSignature = _auxCreatePermitSignature(
            IBridger.Permit(
                _user,
                address(bridger),
                amountToDeposit,
                ERC20Permit(assetToDeposit).nonces(_user),
                block.timestamp + 1000
            ),
            _userPk,
            ERC20Permit(assetToDeposit)
        );

        // UNI to USDe quote's swapData
        // https://api.0x.org/swap/v1/quote?sellToken=0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984&buyToken=0x4c9EDD5852cd905f086C759E8383e09bff1E68B3&sellAmount=1000000000000000000
        bytes memory data =
            hex"6af479b200000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000de0b6b3a7640000000000000000000000000000000000000000000000000000c3e8aa4bcaabba2c000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000421f9840a85d5af5bf1d1762f925bdaddc4201f984000bb8a0b86991c6218b36c1d19d4a2e9eb0ce3606eb480000644c9edd5852cd905f086c759e8383e09bff1e68b3000000000000000000000000000000000000000000000000000000000000869584cd000000000000000000000000100000000000000000000000000000000000001100000000000000000000000000000000417ac500984785634335e679ad0ba662";
        address swapTarget = 0xDef1C0ded9bec7F1a1670819833240f027b25EfF;
        uint256 gasFee = 0 ether;
        IBridger.SwapData memory swapData = IBridger.SwapData(swapTarget, swapTarget, data, gasFee); // spender, swapTarget, swapCallData, gasFee

        // create a bridge signature to allow the bridger to deposit the user's UNI
        IBridger.SignatureData memory sigdata = _auxCreateBridgeSignature(
            kintoWalletL2,
            bridger,
            _user,
            assetToDeposit,
            bridger.sUSDe(),
            amountToDeposit,
            14116720274492340224,
            _userPk,
            block.timestamp + 1000
        );
        uint256 nonce = bridger.nonces(_user);

        vm.prank(_owner);
        bridger.depositBySig{value: gasFee}(permitSignature, sigdata, swapData);

        assertEq(bridger.nonces(_user), nonce + 1);
        assertEq(bridger.deposits(_user, assetToDeposit), 1e18);
        assertEq(ERC20(assetToDeposit).balanceOf(address(bridger)), 0); // there's no UNI since it was swapped

        // preview deposit on 4626 vault
        uint256 shares = ERC4626(bridger.sUSDe()).previewDeposit(14116720274492340224);
        assertApproxEqRel(ERC20(bridger.sUSDe()).balanceOf(address(bridger)), shares, 0.015e18); // 1.5%
    }

    // USDC to sUSDe
    function testDepositBySig_WhenSwap_WhenUSDCTosUSDe() public {
        if (!fork) return;

        vm.rollFork(19408563); // block number in which the 0x API data was fetched
        _deployBridger(); // re-deploy the bridger on block

        // enable swaps
        vm.prank(_owner);
        bridger.setSwapsEnabled(true);

        // whitelist USDC as inputAsset
        address[] memory assets = new address[](1);
        assets[0] = USDC;
        bool[] memory flags = new bool[](1);
        flags[0] = true;
        vm.prank(_owner);
        bridger.whitelistAssets(assets, flags);

        // top-up _user USDC balance (since forge doesn't support doing deal with USDC, we grab a USDC from an account)
        address accountWithUSDC = 0xD6153F5af5679a75cC85D8974463545181f48772;
        address assetToDeposit = USDC;
        uint256 amountToDeposit = 1e6;
        vm.prank(accountWithUSDC);
        ERC20(USDC).transfer(_user, amountToDeposit);

        // create a permit signature to allow the bridger to transfer the user's UNI
        bytes memory permitSignature = _auxCreatePermitSignature(
            IBridger.Permit(
                _user,
                address(bridger),
                amountToDeposit,
                ERC20Permit(assetToDeposit).nonces(_user),
                block.timestamp + 1000
            ),
            _userPk,
            ERC20Permit(assetToDeposit)
        );

        // USDC to USDe quote's swapData
        // https://api.0x.org/swap/v1/quote?sellToken=0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48&buyToken=0x4c9EDD5852cd905f086C759E8383e09bff1E68B3&sellAmount=1000000
        bytes memory data =
            hex"6af479b2000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000f42400000000000000000000000000000000000000000000000000db00b96e10202260000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002ba0b86991c6218b36c1d19d4a2e9eb0ce3606eb480000644c9edd5852cd905f086c759e8383e09bff1e68b3000000000000000000000000000000000000000000869584cd000000000000000000000000100000000000000000000000000000000000001100000000000000000000000000000000ebc4902f950c815797f9229be99af5aa";
        address swapTarget = 0xDef1C0ded9bec7F1a1670819833240f027b25EfF;
        IBridger.SwapData memory swapData = IBridger.SwapData(swapTarget, swapTarget, data, 0); // spender, swapTarget, swapCallData, gasFee

        // create a bridge signature to allow the bridger to deposit the user's UNI
        IBridger.SignatureData memory sigdata = _auxCreateBridgeSignature(
            kintoWalletL2,
            bridger,
            _user,
            assetToDeposit,
            bridger.sUSDe(),
            amountToDeposit,
            996263698022367457,
            _userPk,
            block.timestamp + 1000
        );
        uint256 nonce = bridger.nonces(_user);

        vm.prank(_owner);
        bridger.depositBySig{value: 0}(permitSignature, sigdata, swapData);

        assertEq(bridger.nonces(_user), nonce + 1);
        assertEq(bridger.deposits(_user, assetToDeposit), 1e6);
        assertEq(ERC20(assetToDeposit).balanceOf(address(bridger)), 0); // there's no USDC since it was swapped

        // preview deposit on 4626 vault
        uint256 shares = ERC4626(bridger.sUSDe()).previewDeposit(996263698022367457);
        assertApproxEqRel(ERC20(bridger.sUSDe()).balanceOf(address(bridger)), shares, 0.015e18); // 1.5%
    }

    // stETH to sUSDe
    function testDepositBySig_WhenSwap_WhenStETHTosUSDe() public {
        if (!fork) return;

        vm.rollFork(19447098); // block number in which the 0x API data was fetched
        _deployBridger(); // re-deploy the bridger on block

        // enable swaps
        vm.prank(_owner);
        bridger.setSwapsEnabled(true);

        // whitelist stETH as inputAsset
        address[] memory assets = new address[](1);
        assets[0] = STETH;
        bool[] memory flags = new bool[](1);
        flags[0] = true;
        vm.prank(_owner);
        bridger.whitelistAssets(assets, flags);

        // top-up _user stETH balance (since forge doesn't support doing deal with stETH, we grab a stETH from an account)
        address accountWithStETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
        address assetToDeposit = STETH;
        uint256 amountToDeposit = 1e18;
        vm.prank(accountWithStETH);
        ERC20(assetToDeposit).transfer(_user, amountToDeposit + 1); // +1 because of Lido's 1 wei corner case: https://docs.lido.fi/guides/lido-tokens-integration-guide/#1-2-wei-corner-case

        // create a permit signature to allow the bridger to transfer the user's UNI
        bytes memory permitSignature = _auxCreatePermitSignature(
            IBridger.Permit(
                _user,
                address(bridger),
                amountToDeposit,
                ERC20Permit(assetToDeposit).nonces(_user),
                block.timestamp + 1000
            ),
            _userPk,
            ERC20Permit(assetToDeposit)
        );

        // stETH to USDe quote's swapData
        // https://api.0x.org/swap/v1/quote?sellToken=0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984&buyToken=0x4c9EDD5852cd905f086C759E8383e09bff1E68B3&sellAmount=1000000000000000000
        bytes memory data =
            hex"415565b0000000000000000000000000ae7ab96520de3a18e5e111b5eaab095312d7fe840000000000000000000000004c9edd5852cd905f086c759e8383e09bff1e68b30000000000000000000000000000000000000000000000000de0b6b3a76400000000000000000000000000000000000000000000000000c4729df37ec9b93ef200000000000000000000000000000000000000000000000000000000000000a00000000000000000000000000000000000000000000000000000000000000003000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000003e000000000000000000000000000000000000000000000000000000000000007c000000000000000000000000000000000000000000000000000000000000000210000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000032000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000ae7ab96520de3a18e5e111b5eaab095312d7fe84000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000000000000000000000000000000000000000014000000000000000000000000000000000000000000000000000000000000002e000000000000000000000000000000000000000000000000000000000000002e000000000000000000000000000000000000000000000000000000000000002a00000000000000000000000000000000000000000000000000de0b6b3a7640000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002e00000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000001437572766500000000000000000000000000000000000000000000000000000000000000000000000de0b6b3a7640000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000080000000000000000000000000dc24316b9ae028f1497c275eb9192a3ea0f670223df02124000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000210000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000038000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc20000000000000000000000004c9edd5852cd905f086c759e8383e09bff1e68b30000000000000000000000000000000000000000000000000000000000000140000000000000000000000000000000000000000000000000000000000000034000000000000000000000000000000000000000000000000000000000000003400000000000000000000000000000000000000000000000000000000000000300ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003400000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000012556e6973776170563300000000000000ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff0000000000000000000000000000000000000000000000c4729df37ec9b93ef2000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000000e0000000000000000000000000e592427a0aece92de3edee1f18e0157c05861564000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000042c02aaa39b223fe8d0a0e5c4f27ead9083c756cc20001f4dac17f958d2ee523a2206206994597c13d831ec70000644c9edd5852cd905f086c759e8383e09bff1e68b3000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001c000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000c00000000000000000000000000000000000000000000000000000000000000003000000000000000000000000ae7ab96520de3a18e5e111b5eaab095312d7fe84000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee0000000000000000000000000000000000000000000000000000000000000000869584cd00000000000000000000000010000000000000000000000000000000000000110000000000000000000000000000000053492f68bf3d43cb7271e63cf94db5ed";
        address swapTarget = 0xDef1C0ded9bec7F1a1670819833240f027b25EfF;
        uint256 gasFee = 0 ether;
        IBridger.SwapData memory swapData = IBridger.SwapData(swapTarget, swapTarget, data, gasFee); // spender, swapTarget, swapCallData, gasFee

        // create a bridge signature to allow the bridger to deposit the user's UNI
        IBridger.SignatureData memory sigdata = _auxCreateBridgeSignature(
            kintoWalletL2,
            bridger,
            _user,
            assetToDeposit,
            bridger.sUSDe(),
            amountToDeposit,
            3623820863464615182336,
            _userPk,
            block.timestamp + 1000
        );
        uint256 nonce = bridger.nonces(_user);

        vm.prank(_owner);
        bridger.depositBySig{value: gasFee}(permitSignature, sigdata, swapData);

        assertEq(bridger.nonces(_user), nonce + 1);
        assertEq(bridger.deposits(_user, assetToDeposit), 1e18);
        assertEq(ERC20(assetToDeposit).balanceOf(address(bridger)), 0); // there's no stETH since it was swapped

        // preview deposit on 4626 vault
        uint256 shares = ERC4626(bridger.sUSDe()).previewDeposit(3623820863464615182336);
        assertApproxEqRel(ERC20(bridger.sUSDe()).balanceOf(address(bridger)), shares, 0.015e18); // 1.5%
    }

    function splitSig(bytes memory sig) internal view returns (uint8, bytes32, bytes32) {
        console.log("PERMITTTT");
        console.logBytes(sig);

        uint8 v = uint8(sig[64]); // last byte
        bytes32 r;
        bytes32 s;

        assembly {
            r := mload(add(sig, 32))
            s := mload(add(sig, 64))
        }
        return (v, r, s);
    }

    // UNI to wstETH
    function testDepositBySig_WhenSwap_WhenUNIToWstETH() public {
        if (!fork) return;

        vm.rollFork(19402329); // block number in which the 0x API data was fetched
        _deployBridger(); // re-deploy the bridger on block

        // enable swaps
        vm.prank(_owner);
        bridger.setSwapsEnabled(true);

        // whitelist UNI as inputAsset
        address[] memory assets = new address[](1);
        assets[0] = UNI;
        bool[] memory flags = new bool[](1);
        flags[0] = true;
        vm.prank(_owner);
        bridger.whitelistAssets(assets, flags);

        // top-up _user UNI balance
        address assetToDeposit = UNI;
        uint256 amountToDeposit = 1e18;
        deal(assetToDeposit, _user, amountToDeposit);

        uint256 deadline = block.timestamp + 1000;
        // create a permit signature to allow the bridger to transfer the user's UNI
        bytes memory permitSignature = _auxCreatePermitSignature(
            IBridger.Permit(
                _user, address(bridger), amountToDeposit, ERC20Permit(assetToDeposit).nonces(_user), deadline
            ),
            _userPk,
            ERC20Permit(assetToDeposit)
        );

        // UNI to wstETH quote's swapData
        // https://api.0x.org/swap/v1/quote?sellToken=0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984&buyToken=0x7f39c581f595b53c5cb19bd0b3f8da6c935e2ca0&sellAmount=1000000000000000000
        bytes memory data =
            hex"415565b00000000000000000000000001f9840a85d5af5bf1d1762f925bdaddc4201f9840000000000000000000000007f39c581f595b53c5cb19bd0b3f8da6c935e2ca00000000000000000000000000000000000000000000000000de0b6b3a7640000000000000000000000000000000000000000000000000000000b066ea223b34500000000000000000000000000000000000000000000000000000000000000a00000000000000000000000000000000000000000000000000000000000000003000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000004400000000000000000000000000000000000000000000000000000000000000540000000000000000000000000000000000000000000000000000000000000002100000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000380000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001f9840a85d5af5bf1d1762f925bdaddc4201f9840000000000000000000000007f39c581f595b53c5cb19bd0b3f8da6c935e2ca000000000000000000000000000000000000000000000000000000000000001400000000000000000000000000000000000000000000000000000000000000340000000000000000000000000000000000000000000000000000000000000034000000000000000000000000000000000000000000000000000000000000003000000000000000000000000000000000000000000000000000de0b6b3a7640000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003400000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000012556e69737761705633000000000000000000000000000000000000000000000000000000000000000de0b6b3a7640000000000000000000000000000000000000000000000000000000b0aac13520804000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000000e0000000000000000000000000e592427a0aece92de3edee1f18e0157c058615640000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000421f9840a85d5af5bf1d1762f925bdaddc4201f984000bb8dac17f958d2ee523a2206206994597c13d831ec70001f47f39c581f595b53c5cb19bd0b3f8da6c935e2ca0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001b000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000010000000000000000000000007f39c581f595b53c5cb19bd0b3f8da6c935e2ca00000000000000000000000000000000000000000000000000000043d712e54bf000000000000000000000000ad01c20d5886137e056775af56915de824c8fce5000000000000000000000000000000000000000000000000000000000000001c000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000e00000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000000020000000000000000000000001f9840a85d5af5bf1d1762f925bdaddc4201f984000000000000000000000000eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee0000000000000000000000000000000000000000000000000000000000000000869584cd0000000000000000000000001000000000000000000000000000000000000011000000000000000000000000000000009fad06a693285a6002ba5f7d5d66c41f";
        address swapTarget = 0xDef1C0ded9bec7F1a1670819833240f027b25EfF;
        uint256 gasFee = 0.01 ether;
        IBridger.SwapData memory swapData = IBridger.SwapData(swapTarget, swapTarget, data, gasFee); // spender, swapTarget, swapCallData, gasFee

        // create a bridge signature to allow the bridger to deposit the user's UNI
        IBridger.SignatureData memory sigdata = _auxCreateBridgeSignature(
            kintoWalletL2,
            bridger,
            _user,
            assetToDeposit,
            bridger.wstETH(),
            amountToDeposit,
            3106569413738877,
            _userPk,
            block.timestamp + 1000
        );
        uint256 nonce = bridger.nonces(_user);

        vm.prank(_owner);
        bridger.depositBySig{value: gasFee}(permitSignature, sigdata, swapData);

        assertEq(bridger.nonces(_user), nonce + 1);
        assertEq(bridger.deposits(_user, assetToDeposit), 1e18);
        assertEq(ERC20(assetToDeposit).balanceOf(address(bridger)), 0); // there's no UNI since it was swapped
        assertApproxEqRel(ERC20(bridger.wstETH()).balanceOf(address(bridger)), 3134690504665512, 0.015e18); // 1.5%
    }

    // DAI to wstETH
    function testDepositBySig_WhenSwap_WhenDAItoWstETH() public {
        if (!fork) return;

        vm.rollFork(19402392); // block number in which the 0x API data was fetched
        _deployBridger(); // re-deploy the bridger on block

        // enable swaps
        vm.prank(_owner);
        bridger.setSwapsEnabled(true);

        // whitelist DAI as inputAsset
        address[] memory assets = new address[](1);
        assets[0] = DAI;
        bool[] memory flags = new bool[](1);
        flags[0] = true;
        vm.prank(_owner);
        bridger.whitelistAssets(assets, flags);

        // top-up _user DAI balance
        address assetToDeposit = DAI;
        uint256 amountToDeposit = 1e18;
        deal(assetToDeposit, _user, amountToDeposit);

        // create a permit signature to allow the bridger to transfer the user's DAI
        bytes memory permitSignature = _auxCreatePermitSignature(
            IBridger.Permit(
                _user,
                address(bridger),
                amountToDeposit,
                ERC20Permit(assetToDeposit).nonces(_user),
                block.timestamp + 1000
            ),
            _userPk,
            ERC20Permit(assetToDeposit)
        );

        // create a bridge signature to allow the bridger to deposit the user's DAI
        IBridger.SignatureData memory sigdata = _auxCreateBridgeSignature(
            kintoWalletL2,
            bridger,
            _user,
            assetToDeposit,
            bridger.wstETH(),
            amountToDeposit,
            224787412523677,
            _userPk,
            block.timestamp + 1000
        );
        uint256 nonce = bridger.nonces(_user);

        // DAI to wstETH quote's swapData
        // https://api.0x.org/swap/v1/quote?sellToken=0x6B175474E89094C44Da98b954EedeAC495271d0F&buyToken=0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0&sellAmount=1000000000000000000
        bytes memory data =
            hex"415565b00000000000000000000000006b175474e89094c44da98b954eedeac495271d0f0000000000000000000000007f39c581f595b53c5cb19bd0b3f8da6c935e2ca00000000000000000000000000000000000000000000000000de0b6b3a76400000000000000000000000000000000000000000000000000000000ca653edf7a7b00000000000000000000000000000000000000000000000000000000000000a00000000000000000000000000000000000000000000000000000000000000003000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000500000000000000000000000000000000000000000000000000000000000000002100000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000340000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000000000000000000000000000006b175474e89094c44da98b954eedeac495271d0f0000000000000000000000007f39c581f595b53c5cb19bd0b3f8da6c935e2ca000000000000000000000000000000000000000000000000000000000000001400000000000000000000000000000000000000000000000000000000000000300000000000000000000000000000000000000000000000000000000000000030000000000000000000000000000000000000000000000000000000000000002c00000000000000000000000000000000000000000000000000de0b6b3a7640000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000002537573686953776170000000000000000000000000000000000000000000000000000000000000000de0b6b3a76400000000000000000000000000000000000000000000000000000000cab3150c6cd1000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000d9e1ce17f2641f24ae83637ab66a2cca9c378b9f000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000020000000000000000000000006b175474e89094c44da98b954eedeac495271d0f0000000000000000000000007f39c581f595b53c5cb19bd0b3f8da6c935e2ca0000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001b000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000010000000000000000000000007f39c581f595b53c5cb19bd0b3f8da6c935e2ca00000000000000000000000000000000000000000000000000000004dd62cf256000000000000000000000000ad01c20d5886137e056775af56915de824c8fce5000000000000000000000000000000000000000000000000000000000000001c000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000e00000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000000020000000000000000000000006b175474e89094c44da98b954eedeac495271d0f000000000000000000000000eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee0000000000000000000000000000000000000000000000000000000000000000869584cd0000000000000000000000001000000000000000000000000000000000000011000000000000000000000000000000001687c5412ac490ac6edc10f35363988b";
        address swapTarget = 0xDef1C0ded9bec7F1a1670819833240f027b25EfF;
        uint256 gasFee = 0.01 ether;
        IBridger.SwapData memory swapData = IBridger.SwapData(swapTarget, swapTarget, data, gasFee); // spender, swapTarget, swapCallData, gasFee

        vm.prank(_owner);
        bridger.depositBySig{value: gasFee}(permitSignature, sigdata, swapData);

        assertEq(bridger.nonces(_user), nonce + 1);
        assertEq(bridger.deposits(_user, assetToDeposit), 1e18);
        assertEq(ERC20(assetToDeposit).balanceOf(address(bridger)), 0); // there's no DAI since it was swapped
        assertApproxEqRel(ERC20(bridger.wstETH()).balanceOf(address(bridger)), 224787412523677, 0.015e18); // 1.5%
    }

    function testDepositBySig_RevertWhen_CallerIsNotOwnerOrSender() public {
        address assetToDeposit = bridger.sDAI();
        uint256 amountToDeposit = 1e18;
        deal(address(assetToDeposit), _user, amountToDeposit);

        IBridger.SwapData memory swapData = IBridger.SwapData(address(1), address(1), bytes(""), 0.1 ether);
        IBridger.SignatureData memory sigdata = _auxCreateBridgeSignature(
            kintoWalletL2,
            bridger,
            _user,
            assetToDeposit,
            assetToDeposit,
            amountToDeposit,
            1,
            _userPk,
            block.timestamp + 1000
        );

        vm.expectRevert(IBridger.OnlyOwner.selector);
        vm.prank(_user);
        bridger.depositBySig(bytes(""), sigdata, swapData);
    }

    function testDepositBySig_WhenSwap_WhenInvalidExchangeProxy() public {
        if (!fork) return;

        // enable swaps
        vm.prank(_owner);
        bridger.setSwapsEnabled(true);

        // whitelist UNI as inputAsset
        address[] memory assets = new address[](1);
        assets[0] = UNI;
        bool[] memory flags = new bool[](1);
        flags[0] = true;
        vm.prank(_owner);
        bridger.whitelistAssets(assets, flags);

        // top-up _user UNI balance
        address assetToDeposit = UNI;
        uint256 amountToDeposit = 1e18;
        deal(assetToDeposit, _user, amountToDeposit);

        // create a permit signature to allow the bridger to transfer the user's UNI
        bytes memory permitSignature = _auxCreatePermitSignature(
            IBridger.Permit(
                _user,
                address(bridger),
                amountToDeposit,
                ERC20Permit(assetToDeposit).nonces(_user),
                block.timestamp + 1000
            ),
            _userPk,
            ERC20Permit(assetToDeposit)
        );

        address swapTarget = address(0x123);
        IBridger.SwapData memory swapData = IBridger.SwapData(swapTarget, swapTarget, "0x", 0); // spender, swapTarget, swapCallData, gasFee
        IBridger.SignatureData memory sigdata = _auxCreateBridgeSignature(
            kintoWalletL2,
            bridger,
            _user,
            assetToDeposit,
            bridger.wstETH(),
            amountToDeposit,
            0,
            _userPk,
            block.timestamp + 1000
        );

        vm.expectRevert(IBridger.OnlyExchangeProxy.selector);
        vm.prank(_owner);
        bridger.depositBySig{value: 0}(permitSignature, sigdata, swapData);
    }

    function testDepositBySig_RevertWhen_InputAssetIsNotAllowed() public {
        if (!fork) return;

        address assetToDeposit = DAI;
        uint256 amountToDeposit = 1000e18;

        // disable DAI
        address[] memory assets = new address[](1);
        assets[0] = assetToDeposit;
        bool[] memory flags = new bool[](1);
        flags[0] = false;
        vm.prank(_owner);
        bridger.whitelistAssets(assets, flags);

        IBridger.SwapData memory swapData = IBridger.SwapData(address(1), address(1), bytes(""), 0.1 ether);
        IBridger.SignatureData memory sigdata = _auxCreateBridgeSignature(
            kintoWalletL2,
            bridger,
            _user,
            assetToDeposit,
            bridger.wstETH(),
            amountToDeposit,
            1,
            _userPk,
            block.timestamp + 1000
        );
        bytes memory permitSignature = _auxCreatePermitSignature(
            IBridger.Permit(
                _user,
                address(bridger),
                amountToDeposit,
                ERC20Permit(assetToDeposit).nonces(_user),
                block.timestamp + 1000
            ),
            _userPk,
            ERC20Permit(assetToDeposit)
        );
        vm.prank(_owner);
        vm.expectRevert(IBridger.InvalidAsset.selector);
        bridger.depositBySig(permitSignature, sigdata, swapData);
        vm.stopPrank();
    }

    function testDepositBySig_RevertWhen_InputAssetIsNotAllowed_2() public {
        if (!fork) return;

        address assetToDeposit = DAI;
        uint256 amountToDeposit = 1000e18;

        // disable DAI
        address[] memory assets = new address[](1);
        assets[0] = assetToDeposit;
        bool[] memory flags = new bool[](1);
        flags[0] = false;
        vm.prank(_owner);
        bridger.whitelistAssets(assets, flags);

        IBridger.SwapData memory swapData = IBridger.SwapData(address(1), address(1), bytes(""), 0.1 ether);
        IBridger.SignatureData memory sigdata = _auxCreateBridgeSignature(
            kintoWalletL2,
            bridger,
            _user,
            assetToDeposit,
            bridger.sUSDe(),
            amountToDeposit,
            1,
            _userPk,
            block.timestamp + 1000
        );
        bytes memory permitSignature = _auxCreatePermitSignature(
            IBridger.Permit(
                _user,
                address(bridger),
                amountToDeposit,
                ERC20Permit(assetToDeposit).nonces(_user),
                block.timestamp + 1000
            ),
            _userPk,
            ERC20Permit(assetToDeposit)
        );
        vm.prank(_owner);
        vm.expectRevert(IBridger.InvalidAsset.selector);
        bridger.depositBySig(permitSignature, sigdata, swapData);
        vm.stopPrank();
    }

    function testDepositBySig_RevertWhen_OutputAssetIsNotAllowed() public {
        if (!fork) return;
        address assetToDeposit = DAI;
        uint256 amountToDeposit = 1000e18;
        deal(address(assetToDeposit), _user, amountToDeposit);

        IBridger.SwapData memory swapData = IBridger.SwapData(address(1), address(1), bytes(""), 0.1 ether);
        IBridger.SignatureData memory sigdata = _auxCreateBridgeSignature(
            kintoWalletL2,
            bridger,
            _user,
            assetToDeposit,
            assetToDeposit,
            amountToDeposit,
            amountToDeposit,
            _userPk,
            block.timestamp + 1000
        );
        bytes memory permitSignature = _auxCreatePermitSignature(
            IBridger.Permit(
                _user,
                address(bridger),
                amountToDeposit,
                ERC20Permit(assetToDeposit).nonces(_user),
                block.timestamp + 1000
            ),
            _userPk,
            ERC20Permit(assetToDeposit)
        );
        vm.prank(_owner);
        vm.expectRevert(IBridger.InvalidAsset.selector);
        bridger.depositBySig(permitSignature, sigdata, swapData);
        vm.stopPrank();
    }

    function testDepositBySig_RevertWhen_AmountIsZero() public {
        address assetToDeposit = bridger.sDAI();
        uint256 amountToDeposit = 0;
        deal(address(assetToDeposit), _user, amountToDeposit);

        IBridger.SwapData memory swapData = IBridger.SwapData(address(1), address(1), bytes(""), 0.1 ether);
        IBridger.SignatureData memory sigdata = _auxCreateBridgeSignature(
            kintoWalletL2,
            bridger,
            _user,
            assetToDeposit,
            assetToDeposit,
            amountToDeposit,
            amountToDeposit,
            _userPk,
            block.timestamp + 1000
        );
        bytes memory permitSignature = _auxCreatePermitSignature(
            IBridger.Permit(
                _user,
                address(bridger),
                amountToDeposit,
                ERC20Permit(assetToDeposit).nonces(_user),
                block.timestamp + 1000
            ),
            _userPk,
            ERC20Permit(assetToDeposit)
        );
        vm.expectRevert(IBridger.InvalidAmount.selector);
        vm.prank(_owner);
        bridger.depositBySig(permitSignature, sigdata, swapData);
    }

    /* ============ Bridger ETH Deposit ============ */

    function testDepositETH() public {
        if (!fork) return;
        uint256 gasFee = 0.1 ether;
        uint256 amountToDeposit = 1e18;
        uint256 wstethBalanceBefore = ERC20(bridger.wstETH()).balanceOf(address(bridger));
        vm.deal(_user, amountToDeposit + gasFee);

        vm.startPrank(_user);
        bridger.depositETH{value: amountToDeposit + gasFee}(
            kintoWalletL2, bridger.wstETH(), 1e17, IBridger.SwapData(address(1), address(1), bytes(""), gasFee)
        );
        vm.stopPrank();

        assertEq(bridger.nonces(_user), 0);
        assertEq(bridger.deposits(_user, bridger.ETH()), amountToDeposit);
        uint256 wstethBalance = ERC20(bridger.wstETH()).balanceOf(address(bridger));
        assertTrue(wstethBalance - wstethBalanceBefore > 0);
    }

    function testDepositETH_WhenNoGasFee() public {
        if (!fork) return;
        uint256 gasFee = 0;
        uint256 amountToDeposit = 1e18;
        uint256 wstethBalanceBefore = ERC20(bridger.wstETH()).balanceOf(address(bridger));
        vm.deal(_user, amountToDeposit + gasFee);

        vm.startPrank(_user);
        bridger.depositETH{value: amountToDeposit + gasFee}(
            kintoWalletL2, bridger.wstETH(), 1e17, IBridger.SwapData(address(1), address(1), bytes(""), gasFee)
        );
        vm.stopPrank();

        assertEq(bridger.nonces(_user), 0);
        assertEq(bridger.deposits(_user, bridger.ETH()), amountToDeposit);
        uint256 wstethBalance = ERC20(bridger.wstETH()).balanceOf(address(bridger));
        assertTrue(wstethBalance - wstethBalanceBefore > 0);
    }

    function testDepositETH_WhenSwap_WhenGasFee() public {
        if (!fork) return;

        vm.rollFork(19402998); // block number in which the 0x API data was fetched
        _deployBridger(); // re-deploy the bridger on block

        // enable swaps
        vm.prank(_owner);
        bridger.setSwapsEnabled(true);

        // top-up `_user` ETH balance
        uint256 amountToDeposit = 1.01 ether;
        vm.deal(_user, amountToDeposit);

        // WETH to sDAI quote's swapData
        // https://api.0x.org/swap/v1/quote?sellToken=0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2&buyToken=0x83F20F44975D03b1b09e64809B757c47f942BEeA&sellAmount=1000000000000000000
        bytes memory data =
            hex"415565b0000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc200000000000000000000000083f20f44975d03b1b09e64809b757c47f942beea0000000000000000000000000000000000000000000000000de0b6b3a76400000000000000000000000000000000000000000000000000c8513a48734f22dbe500000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000000030000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000042000000000000000000000000000000000000000000000000000000000000009c000000000000000000000000000000000000000000000000000000000000000210000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000036000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000dac17f958d2ee523a2206206994597c13d831ec700000000000000000000000000000000000000000000000000000000000001400000000000000000000000000000000000000000000000000000000000000320000000000000000000000000000000000000000000000000000000000000032000000000000000000000000000000000000000000000000000000000000002e00000000000000000000000000000000000000000000000000de0b6b3a7640000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003200000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000012556e69737761705633000000000000000000000000000000000000000000000000000000000000000de0b6b3a76400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000000c0000000000000000000000000e592427a0aece92de3edee1f18e0157c0586156400000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000002bc02aaa39b223fe8d0a0e5c4f27ead9083c756cc20001f4dac17f958d2ee523a2206206994597c13d831ec700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000210000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000054000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000dac17f958d2ee523a2206206994597c13d831ec700000000000000000000000083f20f44975d03b1b09e64809b757c47f942beea00000000000000000000000000000000000000000000000000000000000001400000000000000000000000000000000000000000000000000000000000000500000000000000000000000000000000000000000000000000000000000000050000000000000000000000000000000000000000000000000000000000000004c0ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000500000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000001942616c616e6365725632000000000000ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff0000000000000000000000000000000000000000000000c8513a48734f22dbe5000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000002a0000000000000000000000000ba12222222228d8ba445958a75a0704d566bf2c8000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000002200000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000e079c58f70905f734641735bc61e45c19dd9ad60bc0000000000000000000004e7000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000014049cbd67651fbabce12d1df18499896ec87bef46f00000000000000000000064a00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003000000000000000000000000dac17f958d2ee523a2206206994597c13d831ec700000000000000000000000079c58f70905f734641735bc61e45c19dd9ad60bc00000000000000000000000083f20f44975d03b1b09e64809b757c47f942beea000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001c000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000c00000000000000000000000000000000000000000000000000000000000000003000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000dac17f958d2ee523a2206206994597c13d831ec7000000000000000000000000eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee0000000000000000000000000000000000000000000000000000000000000000869584cd00000000000000000000000010000000000000000000000000000000000000110000000000000000000000000000000014e4e350d61dfbf9717023acbafebe4d";
        address swapTarget = 0xDef1C0ded9bec7F1a1670819833240f027b25EfF;
        IBridger.SwapData memory swapData = IBridger.SwapData(swapTarget, swapTarget, data, 0.01 ether); // spender, swapTarget, swapCallData, gasFee

        // uint256 balanceBefore = address(bridger).balance;
        vm.startPrank(_user);
        bridger.depositETH{value: amountToDeposit}(kintoWalletL2, bridger.sDAI(), 3695201885067717640192, swapData);
        vm.stopPrank();

        assertEq(_user.balance, 0);
        assertEq(bridger.deposits(_user, bridger.ETH()), 1e18);
        // assertEq(address(bridger).balance, balanceBefore); // there's no ETH since it was swapped FIXME: there can be some ETH if the gasFee was not used
        assertApproxEqRel(ERC20(bridger.sDAI()).balanceOf(address(bridger)), 3695201885067717640192, 0.01e18); // 1%
    }

    function testDepositETH_WhenSwap_WhenNoGasFee() public {
        if (!fork) return;

        vm.rollFork(19402998); // block number in which the 0x API data was fetched
        _deployBridger(); // re-deploy the bridger on block

        // enable swaps
        vm.prank(_owner);
        bridger.setSwapsEnabled(true);

        // top-up `_user` ETH balance
        uint256 amountToDeposit = 1 ether;
        vm.deal(_user, amountToDeposit);

        // WETH to sDAI quote's swapData
        // https://api.0x.org/swap/v1/quote?sellToken=0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2&buyToken=0x83F20F44975D03b1b09e64809B757c47f942BEeA&sellAmount=1000000000000000000
        bytes memory data =
            hex"415565b0000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc200000000000000000000000083f20f44975d03b1b09e64809b757c47f942beea0000000000000000000000000000000000000000000000000de0b6b3a76400000000000000000000000000000000000000000000000000c8513a48734f22dbe500000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000000030000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000042000000000000000000000000000000000000000000000000000000000000009c000000000000000000000000000000000000000000000000000000000000000210000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000036000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000dac17f958d2ee523a2206206994597c13d831ec700000000000000000000000000000000000000000000000000000000000001400000000000000000000000000000000000000000000000000000000000000320000000000000000000000000000000000000000000000000000000000000032000000000000000000000000000000000000000000000000000000000000002e00000000000000000000000000000000000000000000000000de0b6b3a7640000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003200000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000012556e69737761705633000000000000000000000000000000000000000000000000000000000000000de0b6b3a76400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000000c0000000000000000000000000e592427a0aece92de3edee1f18e0157c0586156400000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000002bc02aaa39b223fe8d0a0e5c4f27ead9083c756cc20001f4dac17f958d2ee523a2206206994597c13d831ec700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000210000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000054000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000dac17f958d2ee523a2206206994597c13d831ec700000000000000000000000083f20f44975d03b1b09e64809b757c47f942beea00000000000000000000000000000000000000000000000000000000000001400000000000000000000000000000000000000000000000000000000000000500000000000000000000000000000000000000000000000000000000000000050000000000000000000000000000000000000000000000000000000000000004c0ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000500000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000001942616c616e6365725632000000000000ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff0000000000000000000000000000000000000000000000c8513a48734f22dbe5000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000002a0000000000000000000000000ba12222222228d8ba445958a75a0704d566bf2c8000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000002200000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000e079c58f70905f734641735bc61e45c19dd9ad60bc0000000000000000000004e7000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000014049cbd67651fbabce12d1df18499896ec87bef46f00000000000000000000064a00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003000000000000000000000000dac17f958d2ee523a2206206994597c13d831ec700000000000000000000000079c58f70905f734641735bc61e45c19dd9ad60bc00000000000000000000000083f20f44975d03b1b09e64809b757c47f942beea000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001c000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000c00000000000000000000000000000000000000000000000000000000000000003000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000dac17f958d2ee523a2206206994597c13d831ec7000000000000000000000000eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee0000000000000000000000000000000000000000000000000000000000000000869584cd00000000000000000000000010000000000000000000000000000000000000110000000000000000000000000000000014e4e350d61dfbf9717023acbafebe4d";
        address swapTarget = 0xDef1C0ded9bec7F1a1670819833240f027b25EfF;
        IBridger.SwapData memory swapData = IBridger.SwapData(swapTarget, swapTarget, data, 0 ether); // spender, swapTarget, swapCallData, gasFee

        uint256 balanceBefore = address(bridger).balance;
        vm.startPrank(_user);
        bridger.depositETH{value: amountToDeposit}(kintoWalletL2, bridger.sDAI(), 3695201885067717640192, swapData);
        vm.stopPrank();

        assertEq(_user.balance, 0);
        assertEq(bridger.deposits(_user, bridger.ETH()), 1e18);
        assertEq(address(bridger).balance, balanceBefore); // there's no ETH since it was swapped
        assertApproxEqRel(ERC20(bridger.sDAI()).balanceOf(address(bridger)), 3695201885067717640192, 0.01e18); // 1%
    }

    function testDepositETH_RevertWhen_FinalAssetisNotAllowed() public {
        uint256 amountToDeposit = 1e18;
        vm.deal(_user, amountToDeposit);
        vm.startPrank(_owner);
        vm.expectRevert(IBridger.InvalidAsset.selector);
        bridger.depositETH{value: amountToDeposit}(
            kintoWalletL2, address(1), 1, IBridger.SwapData(address(1), address(1), bytes(""), 0.1 ether)
        );
        vm.stopPrank();
    }

    function testDepositETH_RevertWhen_AmountIsLessThanAllowed() public {
        uint256 amountToDeposit = 0.05 ether;
        vm.deal(_user, amountToDeposit);
        vm.startPrank(_owner);
        address wsteth = bridger.wstETH();
        vm.expectRevert(IBridger.InvalidAmount.selector);
        bridger.depositETH{value: amountToDeposit}(
            kintoWalletL2, wsteth, 1, IBridger.SwapData(address(1), address(1), bytes(""), 0.1 ether)
        );
        vm.stopPrank();
    }

    /* ============ Whitelist ============ */

    function testWhitelistAsset() public {
        address asset = address(768);
        address[] memory assets = new address[](1);
        assets[0] = asset;
        bool[] memory flags = new bool[](1);
        flags[0] = true;
        vm.prank(_owner);
        bridger.whitelistAssets(assets, flags);
        assertEq(bridger.allowedAssets(asset), true);
    }

    function testWhitelistAsset_RevertWhen_CallerIsNotOwner() public {
        vm.expectRevert("Ownable: caller is not the owner");
        bridger.whitelistAssets(new address[](1), new bool[](1));
    }

    function testWhitelistAsset_RevertWhen_LengthMismatch() public {
        vm.expectRevert(IBridger.InvalidAssets.selector);
        vm.prank(_owner);
        bridger.whitelistAssets(new address[](1), new bool[](2));
    }

    /* ============ Swaps ============ */

    function testSetSwapsEnabled() public {
        vm.prank(_owner);
        bridger.setSwapsEnabled(true);
        assertEq(bridger.swapsEnabled(), true);
    }

    function testSetSwapsEnabled_RevertWhen_CallerIsNotOwner() public {
        vm.startPrank(_user);
        vm.expectRevert("Ownable: caller is not the owner");
        bridger.setSwapsEnabled(true);
        vm.stopPrank();
    }

    /* ============ Bridge ============ */

    function testBridgeDeposits() public {
        if (!fork) return;
        address asset = bridger.sDAI();
        uint256 amountToDeposit = 1e18;
        deal(address(asset), address(bridger), amountToDeposit);

        uint256 kintoMaxGas = 1e6;
        uint256 kintoGasPriceBid = 1e9;
        uint256 kintoMaxSubmissionCost = 1e18;
        uint256 callValue = kintoMaxSubmissionCost + (kintoMaxGas * kintoGasPriceBid);

        vm.prank(_owner);
        bridger.bridgeDeposits{value: callValue}(asset, kintoMaxGas, kintoGasPriceBid, kintoMaxSubmissionCost);

        assertEq(bridger.deposits(_user, asset), 0);
        assertEq(ERC20(asset).balanceOf(address(bridger)), 0);
    }

    function testBridgeDeposits_RevertWhen_InsufficientGas() public {
        address asset = bridger.sDAI();
        uint256 amountToDeposit = 1e18;
        deal(address(asset), address(bridger), amountToDeposit);

        uint256 kintoMaxGas = 1e6;
        uint256 kintoGasPriceBid = 1e9;
        uint256 kintoMaxSubmissionCost = 1e18;

        vm.expectRevert(IBridger.NotEnoughEthToBridge.selector);
        vm.prank(_owner);
        bridger.bridgeDeposits{value: 1}(asset, kintoMaxGas, kintoGasPriceBid, kintoMaxSubmissionCost);
    }

    function testBridgeDeposits_WhenMultipleTimes() public {
        if (!fork) return;

        // array of allowedAssets
        address[4] memory allowedAssets = [bridger.sDAI(), bridger.sUSDe(), bridger.wstETH(), bridger.weETH()];

        uint256 amountToDeposit = 1e18;
        uint256 kintoMaxGas = 1e6;
        uint256 kintoGasPriceBid = 1e9;
        uint256 kintoMaxSubmissionCost = 1e18;
        uint256 callValue = kintoMaxSubmissionCost + (kintoMaxGas * kintoGasPriceBid);

        // for each allowed asset, deposit 1e18 2 times
        for (uint256 i = 0; i < allowedAssets.length; i++) {
            address asset = allowedAssets[i];
            deal(address(asset), address(bridger), amountToDeposit);

            vm.prank(_owner);
            bridger.bridgeDeposits{value: callValue}(asset, kintoMaxGas, kintoGasPriceBid, kintoMaxSubmissionCost);

            assertEq(bridger.deposits(_user, asset), 0);
            assertEq(ERC20(asset).balanceOf(address(bridger)), 0);

            // 2nd time

            vm.prank(_owner);
            bridger.bridgeDeposits{value: callValue}(asset, kintoMaxGas, kintoGasPriceBid, kintoMaxSubmissionCost);

            assertEq(bridger.deposits(_user, asset), 0);
            assertEq(ERC20(asset).balanceOf(address(bridger)), 0);
        }
    }

    /* ============ Pause ============ */

    function testPauseWhenOwner() public {
        assertEq(bridger.paused(), false);
        vm.prank(_owner);
        bridger.pause();
        assertEq(bridger.paused(), true);
    }

    function testPause_RevertWhen_NotOwner() public {
        vm.expectRevert("Ownable: caller is not the owner");
        bridger.pause();
    }

    function testUnpauseWhenOwner() public {
        vm.prank(_owner);
        bridger.pause();

        assertEq(bridger.paused(), true);
        vm.prank(_owner);
        bridger.unpause();
        assertEq(bridger.paused(), false);
    }

    function testUnpause_RevertWhen_NotOwner() public {
        vm.expectRevert("Ownable: caller is not the owner");
        bridger.unpause();
    }

    /* ============ Sender account ============ */

    function testSetSenderAccountWhenOwner() public {
        if (!fork) assertEq(bridger.senderAccount(), senderAccount, "Initial sender account is invalid");

        vm.prank(_owner);
        bridger.setSenderAccount(address(0xdead));
        assertEq(bridger.senderAccount(), address(0xdead), "Sender account invalid address");
    }

    function testSetSenderAccount_RevertWhen_NotOwner() public {
        vm.expectRevert("Ownable: caller is not the owner");
        bridger.setSenderAccount(address(0xdead));
    }

    /* ============ EIP712 ============ */

    function testDomainSeparatorV4() public {
        if (fork) return;
        assertEq(
            bridger.domainSeparatorV4(),
            keccak256(
                abi.encode(
                    keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                    keccak256(bytes("Bridger")), // this contract's name
                    keccak256(bytes("1")), // version
                    block.chainid,
                    address(bridger)
                )
            ),
            "Domain separator is invalid"
        );
    }

    function testHashSignatureData(
        address kintoWallet,
        address signer,
        address inputAsset,
        address finalAsset,
        uint256 amount,
        uint256 minReceive,
        uint256 nonce,
        uint256 expiresAt,
        bytes calldata signature
    ) public {
        if (fork) return;
        IBridger.SignatureData memory data = IBridger.SignatureData({
            kintoWallet: kintoWallet,
            signer: signer,
            inputAsset: inputAsset,
            finalAsset: finalAsset,
            amount: amount,
            minReceive: minReceive,
            nonce: nonce,
            expiresAt: expiresAt,
            signature: signature
        });
        assertEq(
            bridger.hashSignatureData(data),
            keccak256(
                abi.encode(
                    keccak256(
                        "SignatureData(address kintoWallet,address signer,address inputAsset,uint256 amount,uint256 minReceive,address finalAsset,uint256 nonce,uint256 expiresAt)"
                    ),
                    kintoWallet,
                    signer,
                    inputAsset,
                    amount,
                    minReceive,
                    finalAsset,
                    nonce,
                    expiresAt
                )
            ),
            "Signature data is invalid"
        );
    }
}
