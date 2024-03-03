// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../../src/interfaces/IBridger.sol";
import "../../src/bridger/Bridger.sol";

import "../helpers/UUPSProxy.sol";
import "../helpers/TestSignature.sol";
import "../helpers/TestSignature.sol";
import "../SharedSetup.t.sol";

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

contract BridgerNewUpgrade is Bridger {
    function newFunction() external pure returns (uint256) {
        return 1;
    }

    constructor(address l2Vault, address senderAccount) Bridger(l2Vault, senderAccount) {}
}

contract ERCPermitToken is ERC20, ERC20Permit {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) ERC20Permit(name) {}
}

contract BridgerTest is TestSignature, SharedSetup {
    address constant l1ToL2Router = 0xD9041DeCaDcBA88844b373e7053B4AC7A3390D60;
    address constant kintoWalletL2 = address(33);
    address constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant UNI = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984;
    Bridger _bridger;

    error InsufficientValue(uint256 expected, uint256 actual);

    function setUp() public override {
        super.setUp();
        if (fork) {
            string memory rpc = vm.envString("ETHEREUM_RPC_URL");
            require(bytes(rpc).length > 0, "ETHEREUM_RPC_URL is not set");

            vm.chainId(1);
            mainnetFork = vm.createFork(rpc);
            vm.selectFork(mainnetFork);
            assertEq(vm.activeFork(), mainnetFork);
            console.log("Running tests on fork from mainnet at:", rpc);
            vm.roll(19345089); // block number in which the 0x API data was fetched
        }

        // deploy a new Bridger contract
        Bridger implementation = new Bridger(address(99), address(100));
        address proxy = address(new UUPSProxy{salt: 0}(address(implementation), ""));
        _bridger = Bridger(payable(proxy));

        vm.prank(_owner);
        _bridger.initialize();

        // if running local tests, we want to replace some hardcoded addresses that the bridger uses
        // with mocked contracts
        if (!fork) {
            ERCPermitToken sDAI = new ERCPermitToken("sDAI", "sDAI");
            vm.etch(_bridger.sDAI(), address(sDAI).code); // add sDAI code to sDAI address in Bridger
        }
    }

    function testUp() public override {
        // super.testUp();
        assertEq(_bridger.depositCount(), 0);
        assertEq(_bridger.owner(), address(_owner));
        assertEq(_bridger.swapsEnabled(), false);
    }

    /* ============ Upgrade tests ============ */

    function testUpgradeTo() public {
        BridgerNewUpgrade _newImpl = new BridgerNewUpgrade(address(99), address(100));
        vm.prank(_owner);
        _bridger.upgradeTo(address(_newImpl));
        assertEq(BridgerNewUpgrade(payable(address(_bridger))).newFunction(), 1);
    }

    function testUpgradeTo_RevertWhen_CallerIsNotOwner() public {
        BridgerNewUpgrade _newImpl = new BridgerNewUpgrade(address(99), address(100));
        vm.expectRevert(IBridger.OnlyOwner.selector);
        _bridger.upgradeToAndCall(address(_newImpl), bytes(""));
    }

    /* ============ Bridger Deposit tests ============ */

    function testDepositBySig_WhenNoSwap() public {
        address assetToDeposit = _bridger.sDAI();
        uint256 amountToDeposit = 1e18;
        deal(assetToDeposit, _user, amountToDeposit);
        assertEq(ERC20(assetToDeposit).balanceOf(_user), amountToDeposit);
        IBridger.SignatureData memory sigdata = _auxCreateBridgeSignature(
            _bridger, _user, assetToDeposit, amountToDeposit, assetToDeposit, _userPk, block.timestamp + 1000
        );
        bytes memory permitSignature = _auxCreatePermitSignature(
            IBridger.Permit(
                _user,
                address(_bridger),
                amountToDeposit,
                ERC20Permit(assetToDeposit).nonces(_user),
                block.timestamp + 1000
            ),
            _userPk,
            ERC20Permit(assetToDeposit)
        );

        uint256 nonce = _bridger.nonces(_user);
        vm.prank(_owner);
        _bridger.depositBySig(
            kintoWalletL2,
            sigdata,
            IBridger.SwapData(address(1), address(1), bytes(""), 0.1 ether, amountToDeposit),
            permitSignature
        );
        assertEq(_bridger.nonces(_user), nonce + 1);
        assertEq(_bridger.deposits(_user, assetToDeposit), amountToDeposit);
        assertEq(ERC20(assetToDeposit).balanceOf(address(_bridger)), amountToDeposit);
    }

    function testDepositBySig_wtstETHWhenNoSwap() public {
        address assetToDeposit = _bridger.wstETH();
        uint256 amountToDeposit = 1e18;
        deal(assetToDeposit, _user, amountToDeposit);
        assertEq(ERC20(assetToDeposit).balanceOf(_user), amountToDeposit);
        IBridger.SignatureData memory sigdata = _auxCreateBridgeSignature(
            _bridger, _user, assetToDeposit, amountToDeposit, assetToDeposit, _userPk, block.timestamp + 1000
        );
        bytes memory permitSignature = _auxCreatePermitSignature(
            IBridger.Permit(
                _user,
                address(_bridger),
                amountToDeposit,
                ERC20Permit(assetToDeposit).nonces(_user),
                block.timestamp + 1000
            ),
            _userPk,
            ERC20Permit(assetToDeposit)
        );

        uint256 nonce = _bridger.nonces(_user);
        vm.prank(_owner);
        _bridger.depositBySig(
            kintoWalletL2,
            sigdata,
            IBridger.SwapData(address(1), address(1), bytes(""), 0.1 ether, amountToDeposit),
            permitSignature
        );
        assertEq(_bridger.nonces(_user), nonce + 1);
        assertEq(_bridger.deposits(_user, assetToDeposit), amountToDeposit);
        assertEq(ERC20(assetToDeposit).balanceOf(address(_bridger)), amountToDeposit);
    }

    function testDepositBySig_weETHWhenNoSwap() public {
        address assetToDeposit = _bridger.weETH();
        uint256 amountToDeposit = 1e18;
        deal(assetToDeposit, _user, amountToDeposit);
        assertEq(ERC20(assetToDeposit).balanceOf(_user), amountToDeposit);
        IBridger.SignatureData memory sigdata = _auxCreateBridgeSignature(
            _bridger, _user, assetToDeposit, amountToDeposit, assetToDeposit, _userPk, block.timestamp + 1000
        );
        bytes memory permitSignature = _auxCreatePermitSignature(
            IBridger.Permit(
                _user,
                address(_bridger),
                amountToDeposit,
                ERC20Permit(assetToDeposit).nonces(_user),
                block.timestamp + 1000
            ),
            _userPk,
            ERC20Permit(assetToDeposit)
        );

        uint256 nonce = _bridger.nonces(_user);
        vm.prank(_owner);
        _bridger.depositBySig(
            kintoWalletL2,
            sigdata,
            IBridger.SwapData(address(1), address(1), bytes(""), 0.1 ether, amountToDeposit),
            permitSignature
        );
        assertEq(_bridger.nonces(_user), nonce + 1);
        assertEq(_bridger.deposits(_user, assetToDeposit), amountToDeposit);
        assertEq(ERC20(assetToDeposit).balanceOf(address(_bridger)), amountToDeposit);
    }

    function testDepositBySig_sUSDeWhenNoSwap() public {
        address assetToDeposit = _bridger.sUSDe();
        uint256 amountToDeposit = 1e18;
        deal(assetToDeposit, _user, amountToDeposit);
        assertEq(ERC20(assetToDeposit).balanceOf(_user), amountToDeposit);
        IBridger.SignatureData memory sigdata = _auxCreateBridgeSignature(
            _bridger, _user, assetToDeposit, amountToDeposit, assetToDeposit, _userPk, block.timestamp + 1000
        );
        bytes memory permitSignature = _auxCreatePermitSignature(
            IBridger.Permit(
                _user,
                address(_bridger),
                amountToDeposit,
                ERC20Permit(assetToDeposit).nonces(_user),
                block.timestamp + 1000
            ),
            _userPk,
            ERC20Permit(assetToDeposit)
        );

        uint256 nonce = _bridger.nonces(_user);
        vm.prank(_owner);
        _bridger.depositBySig(
            kintoWalletL2,
            sigdata,
            IBridger.SwapData(address(1), address(1), bytes(""), 0.1 ether, amountToDeposit),
            permitSignature
        );
        assertEq(_bridger.nonces(_user), nonce + 1);
        assertEq(_bridger.deposits(_user, assetToDeposit), amountToDeposit);
        assertEq(ERC20(assetToDeposit).balanceOf(address(_bridger)), amountToDeposit);
    }

    function testDepositBySig_USDeWhenNoSwap() public {
        address assetToDeposit = _bridger.USDe();
        uint256 amountToDeposit = 1e18;
        deal(assetToDeposit, _user, amountToDeposit);
        assertEq(ERC20(assetToDeposit).balanceOf(_user), amountToDeposit);
        IBridger.SignatureData memory sigdata = _auxCreateBridgeSignature(
            _bridger, _user, assetToDeposit, amountToDeposit, _bridger.sUSDe(), _userPk, block.timestamp + 1000
        );
        bytes memory permitSignature = _auxCreatePermitSignature(
            IBridger.Permit(
                _user,
                address(_bridger),
                amountToDeposit,
                ERC20Permit(assetToDeposit).nonces(_user),
                block.timestamp + 1000
            ),
            _userPk,
            ERC20Permit(assetToDeposit)
        );

        uint256 nonce = _bridger.nonces(_user);
        vm.prank(_owner);
        _bridger.depositBySig(
            kintoWalletL2,
            sigdata,
            IBridger.SwapData(address(1), address(1), bytes(""), 0.1 ether, 1e17),
            permitSignature
        );
        assertEq(_bridger.nonces(_user), nonce + 1);
        assertEq(_bridger.deposits(_user, assetToDeposit), amountToDeposit);
        assertEq(ERC20(_bridger.sUSDe()).balanceOf(address(_bridger)) > 0, true);
    }

    function testDepositBySig_WhenSwap() public {
        if (!fork) return;

        // enable swaps
        vm.prank(_owner);
        _bridger.setSwapsEnabled(true);

        // whitelist UNI as inputAsset
        address[] memory assets = new address[](1);
        assets[0] = UNI;
        bool[] memory flags = new bool[](1);
        flags[0] = true;
        vm.prank(_owner);
        _bridger.whitelistAssets(assets, flags);

        // top-up _user UNI balance
        address assetToDeposit = UNI;
        uint256 amountToDeposit = 1e18;
        deal(assetToDeposit, _user, amountToDeposit);

        // create a permit signature to allow the bridger to transfer the user's UNI
        bytes memory permitSignature = _auxCreatePermitSignature(
            IBridger.Permit(
                _user,
                address(_bridger),
                amountToDeposit,
                ERC20Permit(assetToDeposit).nonces(_user),
                block.timestamp + 1000
            ),
            _userPk,
            ERC20Permit(assetToDeposit)
        );

        // create a bridge signature to allow the bridger to deposit the user's UNI
        IBridger.SignatureData memory sigdata = _auxCreateBridgeSignature(
            _bridger, _user, assetToDeposit, amountToDeposit, _bridger.wstETH(), _userPk, block.timestamp + 1000
        );
        uint256 nonce = _bridger.nonces(_user);

        // UNI to wstETH quote's swapData
        // https://api.0x.org/swap/v1/quote?sellToken=0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984&buyToken=0x7f39c581f595b53c5cb19bd0b3f8da6c935e2ca0&sellAmount=1000000000000000000
        bytes memory data =
            hex"415565b00000000000000000000000001f9840a85d5af5bf1d1762f925bdaddc4201f9840000000000000000000000007f39c581f595b53c5cb19bd0b3f8da6c935e2ca00000000000000000000000000000000000000000000000000de0b6b3a7640000000000000000000000000000000000000000000000000000000af61dbe06ed9200000000000000000000000000000000000000000000000000000000000000a00000000000000000000000000000000000000000000000000000000000000003000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000004400000000000000000000000000000000000000000000000000000000000000540000000000000000000000000000000000000000000000000000000000000002100000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000380000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001f9840a85d5af5bf1d1762f925bdaddc4201f9840000000000000000000000007f39c581f595b53c5cb19bd0b3f8da6c935e2ca000000000000000000000000000000000000000000000000000000000000001400000000000000000000000000000000000000000000000000000000000000340000000000000000000000000000000000000000000000000000000000000034000000000000000000000000000000000000000000000000000000000000003000000000000000000000000000000000000000000000000000de0b6b3a7640000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003400000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000012556e69737761705633000000000000000000000000000000000000000000000000000000000000000de0b6b3a7640000000000000000000000000000000000000000000000000000000afa54e8df53b6000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000000e0000000000000000000000000e592427a0aece92de3edee1f18e0157c058615640000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000421f9840a85d5af5bf1d1762f925bdaddc4201f984002710c02aaa39b223fe8d0a0e5c4f27ead9083c756cc20001f47f39c581f595b53c5cb19bd0b3f8da6c935e2ca0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001b000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000010000000000000000000000007f39c581f595b53c5cb19bd0b3f8da6c935e2ca0000000000000000000000000000000000000000000000000000004372ad86624000000000000000000000000ad01c20d5886137e056775af56915de824c8fce5000000000000000000000000000000000000000000000000000000000000001c000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000e00000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000000020000000000000000000000001f9840a85d5af5bf1d1762f925bdaddc4201f984000000000000000000000000eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee0000000000000000000000000000000000000000000000000000000000000000869584cd0000000000000000000000001000000000000000000000000000000000000011000000000000000000000000000000008e47f81eb2c0646234fd8472728af57e";
        address swapTarget = 0xDef1C0ded9bec7F1a1670819833240f027b25EfF;
        uint256 gasFee = 0.01 ether;
        IBridger.SwapData memory swapData = IBridger.SwapData(swapTarget, swapTarget, data, gasFee, 3106569413738877); // spender, swapTarget, swapCallData, gasFee

        vm.prank(_owner);
        _bridger.depositBySig{value: gasFee}(kintoWalletL2, sigdata, swapData, permitSignature);

        assertEq(_bridger.nonces(_user), nonce + 1);
        assertEq(_bridger.deposits(_user, assetToDeposit), 1e18);
        assertEq(ERC20(assetToDeposit).balanceOf(address(_bridger)), 0); // there's no UNI since it was swapped
        assertApproxEqRel(ERC20(_bridger.wstETH()).balanceOf(address(_bridger)), 3116569413738877, 0.015e18); // 1.5%
    }

    function testDepositBySig_RevertWhen_CallerIsNotOwnerOrSender() public {
        address assetToDeposit = _bridger.sDAI();
        uint256 amountToDeposit = 1e18;
        deal(address(assetToDeposit), _user, amountToDeposit);
        IBridger.SignatureData memory sigdata = _auxCreateBridgeSignature(
            _bridger, _user, assetToDeposit, amountToDeposit, assetToDeposit, _userPk, block.timestamp + 1000
        );
        vm.startPrank(_user);
        vm.expectRevert(IBridger.OnlyOwner.selector);
        _bridger.depositBySig(
            kintoWalletL2, sigdata, IBridger.SwapData(address(1), address(1), bytes(""), 0.1 ether, 1), bytes("")
        );
        vm.stopPrank();
    }

    function testDepositBySig_RevertWhen_InputAssetIsNotAllowed() public {
        address assetToDeposit = DAI;
        uint256 amountToDeposit = 1000e18;
        deal(address(assetToDeposit), _user, amountToDeposit);
        IBridger.SignatureData memory sigdata = _auxCreateBridgeSignature(
            _bridger, _user, assetToDeposit, amountToDeposit, _bridger.wstETH(), _userPk, block.timestamp + 1000
        );
        bytes memory permitSignature = _auxCreatePermitSignature(
            IBridger.Permit(
                _user,
                address(_bridger),
                amountToDeposit,
                ERC20Permit(assetToDeposit).nonces(_user),
                block.timestamp + 1000
            ),
            _userPk,
            ERC20Permit(assetToDeposit)
        );
        vm.prank(_owner);
        vm.expectRevert(IBridger.InvalidAsset.selector);
        _bridger.depositBySig(
            kintoWalletL2, sigdata, IBridger.SwapData(address(1), address(1), bytes(""), 0.1 ether, 1), permitSignature
        );
        vm.stopPrank();
    }

    function testDepositBySig_RevertWhen_OutputAssetIsNotAllowed() public {
        address assetToDeposit = DAI;
        uint256 amountToDeposit = 1000e18;
        deal(address(assetToDeposit), _user, amountToDeposit);
        IBridger.SignatureData memory sigdata = _auxCreateBridgeSignature(
            _bridger, _user, assetToDeposit, amountToDeposit, assetToDeposit, _userPk, block.timestamp + 1000
        );
        bytes memory permitSignature = _auxCreatePermitSignature(
            IBridger.Permit(
                _user,
                address(_bridger),
                amountToDeposit,
                ERC20Permit(assetToDeposit).nonces(_user),
                block.timestamp + 1000
            ),
            _userPk,
            ERC20Permit(assetToDeposit)
        );
        vm.prank(_owner);
        vm.expectRevert(IBridger.InvalidAsset.selector);
        _bridger.depositBySig(
            kintoWalletL2, sigdata, IBridger.SwapData(address(1), address(1), bytes(""), 0.1 ether, 1), permitSignature
        );
        vm.stopPrank();
    }

    function testDepositBySig_RevertWhen_AmountIsZero() public {
        address assetToDeposit = _bridger.sDAI();
        uint256 amountToDeposit = 0;
        deal(address(assetToDeposit), _user, amountToDeposit);
        IBridger.SignatureData memory sigdata = _auxCreateBridgeSignature(
            _bridger, _user, assetToDeposit, amountToDeposit, assetToDeposit, _userPk, block.timestamp + 1000
        );
        bytes memory permitSignature = _auxCreatePermitSignature(
            IBridger.Permit(
                _user,
                address(_bridger),
                amountToDeposit,
                ERC20Permit(assetToDeposit).nonces(_user),
                block.timestamp + 1000
            ),
            _userPk,
            ERC20Permit(assetToDeposit)
        );
        vm.prank(_owner);
        vm.expectRevert(IBridger.InvalidAmount.selector);
        _bridger.depositBySig(
            kintoWalletL2, sigdata, IBridger.SwapData(address(1), address(1), bytes(""), 0.1 ether, 1), permitSignature
        );
        vm.stopPrank();
    }

    /* ============ Bridger ETH Deposit Tests ============ */

    function testDepositETH() public {
        uint256 gasFee = 0.1 ether;
        uint256 amountToDeposit = 1e18;
        vm.deal(_user, amountToDeposit + gasFee);

        vm.startPrank(_user);
        _bridger.depositETH{value: amountToDeposit + gasFee}(
            kintoWalletL2, _bridger.wstETH(), IBridger.SwapData(address(1), address(1), bytes(""), gasFee, 1e17)
        );
        vm.stopPrank();

        assertEq(_bridger.nonces(_user), 0);
        assertEq(_bridger.deposits(_user, _bridger.ETH()), amountToDeposit);
        uint256 wstethBalance = ERC20(_bridger.wstETH()).balanceOf(address(_bridger));
        assertEq(wstethBalance > 0 && wstethBalance < amountToDeposit, true);
    }

    function testDepositETH_WhenNoGasFee() public {
        uint256 gasFee = 0;
        uint256 amountToDeposit = 1e18;
        vm.deal(_user, amountToDeposit + gasFee);

        vm.startPrank(_user);
        _bridger.depositETH{value: amountToDeposit + gasFee}(
            kintoWalletL2, _bridger.wstETH(), IBridger.SwapData(address(1), address(1), bytes(""), gasFee, 1e17)
        );
        vm.stopPrank();

        assertEq(_bridger.nonces(_user), 0);
        assertEq(_bridger.deposits(_user, _bridger.ETH()), amountToDeposit);
        uint256 wstethBalance = ERC20(_bridger.wstETH()).balanceOf(address(_bridger));
        assertEq(wstethBalance > 0 && wstethBalance < amountToDeposit, true);
    }

    function testDepositETH_WhenSwap_WhenGasFee() public {
        if (!fork) return;

        // enable swaps
        vm.prank(_owner);
        _bridger.setSwapsEnabled(true);

        // top-up `_user` ETH balance
        uint256 amountToDeposit = 1.01 ether;
        vm.deal(_user, amountToDeposit);

        // WETH to sDAI quote's swapData
        // https://api.0x.org/swap/v1/quote?sellToken=0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2&buyToken=0x83F20F44975D03b1b09e64809B757c47f942BEeA&sellAmount=1000000000000000000
        bytes memory data =
            hex"415565b0000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc200000000000000000000000083f20f44975d03b1b09e64809b757c47f942beea0000000000000000000000000000000000000000000000000de0b6b3a76400000000000000000000000000000000000000000000000000ae87efa206390c8b8300000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000000030000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000042000000000000000000000000000000000000000000000000000000000000009c000000000000000000000000000000000000000000000000000000000000000210000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000036000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb4800000000000000000000000000000000000000000000000000000000000001400000000000000000000000000000000000000000000000000000000000000320000000000000000000000000000000000000000000000000000000000000032000000000000000000000000000000000000000000000000000000000000002e00000000000000000000000000000000000000000000000000de0b6b3a7640000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003200000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000012556e69737761705633000000000000000000000000000000000000000000000000000000000000000de0b6b3a76400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000000c0000000000000000000000000e592427a0aece92de3edee1f18e0157c0586156400000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000002bc02aaa39b223fe8d0a0e5c4f27ead9083c756cc20001f4a0b86991c6218b36c1d19d4a2e9eb0ce3606eb4800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000210000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000054000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb4800000000000000000000000083f20f44975d03b1b09e64809b757c47f942beea00000000000000000000000000000000000000000000000000000000000001400000000000000000000000000000000000000000000000000000000000000500000000000000000000000000000000000000000000000000000000000000050000000000000000000000000000000000000000000000000000000000000004c0ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000500000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000001942616c616e6365725632000000000000ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff0000000000000000000000000000000000000000000000ae87efa206390c8b83000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000002a0000000000000000000000000ba12222222228d8ba445958a75a0704d566bf2c8000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000002200000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000e079c58f70905f734641735bc61e45c19dd9ad60bc0000000000000000000004e7000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000014049cbd67651fbabce12d1df18499896ec87bef46f00000000000000000000064a00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb4800000000000000000000000079c58f70905f734641735bc61e45c19dd9ad60bc00000000000000000000000083f20f44975d03b1b09e64809b757c47f942beea000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001c000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000c00000000000000000000000000000000000000000000000000000000000000003000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48000000000000000000000000eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee0000000000000000000000000000000000000000000000000000000000000000869584cd0000000000000000000000001000000000000000000000000000000000000011000000000000000000000000000000009f2f9e10c8f5b54f4e7a1fd7532a80c1";
        address swapTarget = 0xDef1C0ded9bec7F1a1670819833240f027b25EfF;
        IBridger.SwapData memory swapData =
            IBridger.SwapData(swapTarget, swapTarget, data, 0.01 ether, 3202049186553158309369); // spender, swapTarget, swapCallData, gasFee

        // uint256 balanceBefore = address(_bridger).balance;
        vm.startPrank(_user);
        _bridger.depositETH{value: amountToDeposit}(kintoWalletL2, _bridger.sDAI(), swapData);
        vm.stopPrank();

        assertEq(_user.balance, 0);
        assertEq(_bridger.deposits(_user, _bridger.ETH()), 1e18);
        // assertEq(address(_bridger).balance, balanceBefore); // there's no ETH since it was swapped FIXME: there can be some ETH if the gasFee was not used
        assertApproxEqRel(ERC20(_bridger.sDAI()).balanceOf(address(_bridger)), 3252049186553158309369, 0.01e18); // 1%
    }

    function testDepositETH_WhenSwap_WhenNoGasFee() public {
        if (!fork) return;

        // enable swaps
        vm.prank(_owner);
        _bridger.setSwapsEnabled(true);

        // top-up `_user` ETH balance
        uint256 amountToDeposit = 1 ether;
        vm.deal(_user, amountToDeposit);

        // WETH to sDAI quote's swapData
        // https://api.0x.org/swap/v1/quote?sellToken=0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2&buyToken=0x83F20F44975D03b1b09e64809B757c47f942BEeA&sellAmount=1000000000000000000
        bytes memory data =
            hex"415565b0000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc200000000000000000000000083f20f44975d03b1b09e64809b757c47f942beea0000000000000000000000000000000000000000000000000de0b6b3a76400000000000000000000000000000000000000000000000000ae87efa206390c8b8300000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000000030000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000042000000000000000000000000000000000000000000000000000000000000009c000000000000000000000000000000000000000000000000000000000000000210000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000036000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb4800000000000000000000000000000000000000000000000000000000000001400000000000000000000000000000000000000000000000000000000000000320000000000000000000000000000000000000000000000000000000000000032000000000000000000000000000000000000000000000000000000000000002e00000000000000000000000000000000000000000000000000de0b6b3a7640000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003200000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000012556e69737761705633000000000000000000000000000000000000000000000000000000000000000de0b6b3a76400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000000c0000000000000000000000000e592427a0aece92de3edee1f18e0157c0586156400000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000002bc02aaa39b223fe8d0a0e5c4f27ead9083c756cc20001f4a0b86991c6218b36c1d19d4a2e9eb0ce3606eb4800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000210000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000054000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb4800000000000000000000000083f20f44975d03b1b09e64809b757c47f942beea00000000000000000000000000000000000000000000000000000000000001400000000000000000000000000000000000000000000000000000000000000500000000000000000000000000000000000000000000000000000000000000050000000000000000000000000000000000000000000000000000000000000004c0ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000500000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000001942616c616e6365725632000000000000ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff0000000000000000000000000000000000000000000000ae87efa206390c8b83000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000002a0000000000000000000000000ba12222222228d8ba445958a75a0704d566bf2c8000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000002200000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000e079c58f70905f734641735bc61e45c19dd9ad60bc0000000000000000000004e7000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000014049cbd67651fbabce12d1df18499896ec87bef46f00000000000000000000064a00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb4800000000000000000000000079c58f70905f734641735bc61e45c19dd9ad60bc00000000000000000000000083f20f44975d03b1b09e64809b757c47f942beea000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001c000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000c00000000000000000000000000000000000000000000000000000000000000003000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48000000000000000000000000eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee0000000000000000000000000000000000000000000000000000000000000000869584cd0000000000000000000000001000000000000000000000000000000000000011000000000000000000000000000000009f2f9e10c8f5b54f4e7a1fd7532a80c1";
        address swapTarget = 0xDef1C0ded9bec7F1a1670819833240f027b25EfF;
        IBridger.SwapData memory swapData =
            IBridger.SwapData(swapTarget, swapTarget, data, 0 ether, 3202049186553158309369); // spender, swapTarget, swapCallData, gasFee

        uint256 balanceBefore = address(_bridger).balance;
        vm.startPrank(_user);
        _bridger.depositETH{value: amountToDeposit}(kintoWalletL2, _bridger.sDAI(), swapData);
        vm.stopPrank();

        assertEq(_user.balance, 0);
        assertEq(_bridger.deposits(_user, _bridger.ETH()), 1e18);
        assertEq(address(_bridger).balance, balanceBefore); // there's no ETH since it was swapped
        assertApproxEqRel(ERC20(_bridger.sDAI()).balanceOf(address(_bridger)), 3252049186553158309369, 0.01e18); // 1%
    }

    function testDepositETH_RevertWhen_FinalAssetisNotAllowed() public {
        uint256 amountToDeposit = 1e18;
        vm.deal(_user, amountToDeposit);
        vm.startPrank(_owner);
        vm.expectRevert(IBridger.InvalidAsset.selector);
        _bridger.depositETH{value: amountToDeposit}(
            kintoWalletL2, address(1), IBridger.SwapData(address(1), address(1), bytes(""), 0.1 ether, 1)
        );
        vm.stopPrank();
    }

    function testDepositETH_RevertWhen_AmountIsLessThanAllowed() public {
        uint256 amountToDeposit = 0.05 ether;
        vm.deal(_user, amountToDeposit);
        vm.startPrank(_owner);
        address wsteth = _bridger.wstETH();
        vm.expectRevert(IBridger.InvalidAmount.selector);
        _bridger.depositETH{value: amountToDeposit}(
            kintoWalletL2, wsteth, IBridger.SwapData(address(1), address(1), bytes(""), 0.1 ether, 1)
        );
        vm.stopPrank();
    }

    /* ============ Whitelist tests ============ */

    function testWhitelistAsset() public {
        address asset = address(768);
        vm.prank(_owner);
        address[] memory assets = new address[](1);
        assets[0] = asset;
        bool[] memory flags = new bool[](1);
        flags[0] = true;
        _bridger.whitelistAssets(assets, flags);
        assertEq(_bridger.allowedAssets(asset), true);
    }

    function testWhitelistAsset_RevertWhen_CallerIsNotOwner() public {
        vm.expectRevert("Ownable: caller is not the owner");
        _bridger.whitelistAssets(new address[](1), new bool[](1));
    }

    /* ============ Emergency Withdrawal tests ============ */

    function testEmergencyExit() public {
        uint256 amountToDeposit = 1e18;
        vm.deal(_user, amountToDeposit);
        vm.startPrank(_user);
        _bridger.depositETH{value: amountToDeposit}(
            kintoWalletL2, _bridger.wstETH(), IBridger.SwapData(address(1), address(1), bytes(""), 0.1 ether, 1)
        );
        uint256 wstethBalance = ERC20(_bridger.wstETH()).balanceOf(address(_bridger));
        vm.startPrank(_owner);
        _bridger.emergencyExit(_bridger.wstETH());
        assertEq(ERC20(_bridger.wstETH()).balanceOf(address(_bridger)), 0);
        assertEq(ERC20(_bridger.wstETH()).balanceOf(address(_owner)), wstethBalance);
        vm.stopPrank();
    }

    function testEmergencyExit_RetrievesETH() public {
        uint256 amountToDeposit = 6e18;
        vm.deal(address(_bridger), amountToDeposit);

        uint256 beforeBalance = _owner.balance;
        vm.startPrank(_owner);
        _bridger.emergencyExit(_bridger.ETH());
        vm.stopPrank();

        assertEq(payable(_bridger).balance, 0);
        assertEq(_owner.balance, beforeBalance + 6e18);
    }

    function testEmergencyExit_RevertWhen_CallerIsNotOwner() public {
        vm.startPrank(_user);
        address wsteth = _bridger.wstETH();
        vm.expectRevert();
        _bridger.emergencyExit(wsteth);
        vm.stopPrank();
    }

    /* ============ Swaps enabled tests ============ */

    function testSetSwapsEnabled() public {
        vm.prank(_owner);
        _bridger.setSwapsEnabled(true);
        assertEq(_bridger.swapsEnabled(), true);
    }

    function testSetSwapsEnabled_RevertWhen_CallerIsNotOwner() public {
        vm.startPrank(_user);
        vm.expectRevert();
        _bridger.setSwapsEnabled(true);
        vm.stopPrank();
    }

    /* ============ Bridge tests ============ */

    function testBridgeDeposits() public {
        address asset = _bridger.sDAI();
        uint256 amountToDeposit = 1e18;
        deal(address(asset), address(_bridger), amountToDeposit);

        uint256 kintoMaxGas = 1e6;
        uint256 kintoGasPriceBid = 1e9;
        uint256 kintoMaxSubmissionCost = 1e18;
        uint256 callValue = kintoMaxSubmissionCost + (kintoMaxGas * kintoGasPriceBid);

        vm.prank(_owner);
        _bridger.bridgeDeposits{value: callValue}(asset, kintoMaxGas, kintoGasPriceBid, kintoMaxSubmissionCost);

        assertEq(_bridger.deposits(_user, asset), 0);
        assertEq(ERC20(asset).balanceOf(address(_bridger)), 0);
    }

    function testBridgeDeposits_RevertWhen_InsufficientGas() public {
        address asset = _bridger.sDAI();
        uint256 amountToDeposit = 1e18;
        deal(address(asset), address(_bridger), amountToDeposit);

        uint256 kintoMaxGas = 1e6;
        uint256 kintoGasPriceBid = 1e9;
        uint256 kintoMaxSubmissionCost = 1e18;

        vm.expectRevert(IBridger.NotEnoughEthToBridge.selector);
        vm.prank(_owner);
        _bridger.bridgeDeposits{value: 1}(asset, kintoMaxGas, kintoGasPriceBid, kintoMaxSubmissionCost);
    }

    // todo: test pause and setSender account
}
