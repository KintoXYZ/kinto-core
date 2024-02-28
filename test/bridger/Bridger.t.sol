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

    constructor() Bridger() {}
}

contract ERCPermitToken is ERC20, ERC20Permit {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) ERC20Permit(name) {}
}

contract BridgerTest is TestSignature, SharedSetup {
    address constant l1ToL2Router = 0xD9041DeCaDcBA88844b373e7053B4AC7A3390D60;
    address constant kintoWalletL2 = address(33);
    Bridger _bridger;

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
        }

        vm.startPrank(_owner);
        Bridger implementation = new Bridger();
        address proxy = address(new UUPSProxy{salt: 0}(address(implementation), ""));
        _bridger = Bridger(payable(proxy));
        _bridger.initialize();
        vm.stopPrank();

        if (!fork) {
            ERCPermitToken sDAI = new ERCPermitToken("sDAI", "sDAI");
            vm.etch(_bridger.sDAI(), address(sDAI).code); // add sDAI code to sDAI address in Bridger
        }
    }

    function testUp() public override {
        super.testUp();
        assertEq(_bridger.depositCount(), 0);
        assertEq(_bridger.owner(), address(_owner));
    }

    /* ============ Upgrade tests ============ */

    function testUpgradeTo() public {
        BridgerNewUpgrade _newImpl = new BridgerNewUpgrade();
        vm.prank(_owner);
        _bridger.upgradeTo(address(_newImpl));
        assertEq(BridgerNewUpgrade(payable(address(_bridger))).newFunction(), 1);
    }

    function testUpgradeTo_RevertWhen_CallerIsNotOwner() public {
        BridgerNewUpgrade _newImpl = new BridgerNewUpgrade();
        vm.expectRevert(IBridger.OnlyOwner.selector);
        _bridger.upgradeToAndCall(address(_newImpl), bytes(""));
    }

    /* ============ Bridger Deposit By Sig tests ============ */

    function testDirectDepositBySigWithoutSwap_WhenCallingViaSig() public {
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
            kintoWalletL2, sigdata, IBridger.SwapData(address(1), address(1), bytes("")), permitSignature
        );
        assertEq(_bridger.nonces(_user), nonce + 1);
        assertEq(_bridger.deposits(_user, assetToDeposit), amountToDeposit);
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
        _bridger.depositBySig(kintoWalletL2, sigdata, IBridger.SwapData(address(1), address(1), bytes("")), bytes(""));
        vm.stopPrank();
    }

    function testDepositBySig_RevertWhen_AssetIsNotAllowed() public {
        address assetToDeposit = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
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
            kintoWalletL2, sigdata, IBridger.SwapData(address(1), address(1), bytes("")), permitSignature
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
            kintoWalletL2, sigdata, IBridger.SwapData(address(1), address(1), bytes("")), permitSignature
        );
        vm.stopPrank();
    }

    /* ============ Withdraw tests ============ */
}
