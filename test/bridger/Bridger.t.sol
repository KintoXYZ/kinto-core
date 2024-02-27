// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../../src/interfaces/IBridger.sol";
import "../../src/bridger/Bridger.sol";
import "../helpers/UUPSProxy.sol";
import "../helpers/TestSignature.sol";

contract BridgerNewUpgrade is Bridger {
    function newFunction() external pure returns (uint256) {
        return 1;
    }

    constructor() Bridger() {}
}

contract BridgerTest is TestSignature {
    // private keys
    uint256 _ownerPk = 1;
    uint256 _secondownerPk = 2;
    uint256 _userPk = 3;
    uint256 _user2Pk = 4;
    uint256 _upgraderPk = 5;
    uint256 _kycProviderPk = 6;
    uint256 _recovererPk = 7;
    uint256 _funderPk = 8;
    uint256 _noKycPk = 9;

    // users
    address payable _owner = payable(vm.addr(_ownerPk));
    address payable _secondowner = payable(vm.addr(_secondownerPk));
    address payable _user = payable(vm.addr(_userPk));
    address payable _user2 = payable(vm.addr(_user2Pk));
    address payable _upgrader = payable(vm.addr(_upgraderPk));
    address payable _kycProvider = payable(vm.addr(_kycProviderPk));
    address payable _recoverer = payable(vm.addr(_recovererPk));
    address payable _funder = payable(vm.addr(_funderPk));
    address payable _noKyc = payable(vm.addr(_noKycPk));

    address constant l1ToL2Router = 0xD9041DeCaDcBA88844b373e7053B4AC7A3390D60;
    address constant kintoWalletL2 = address(33);
    Bridger _bridger;

    constructor() {
        vm.startPrank(_owner);
        Bridger implementation = new Bridger();
        address proxy = address(new UUPSProxy{salt: 0}(address(implementation), ""));
        _bridger = Bridger(payable(proxy));
        _bridger.initialize();
        vm.stopPrank();
    }

    function testUp() public {
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

    /* ============ Bridger Deposit tests ============ */

    function testDirectDepositBySigWithoutSwap_WhenCallingViaSig() public {
        address assetToDeposit = _bridger.sDAI();
        uint256 amountToDeposit = 1e18;
        deal(assetToDeposit, _user, amountToDeposit);
        assertEq(ERC20(assetToDeposit).balanceOf(_user), amountToDeposit);
        IBridger.SignatureData memory sigdata = _auxCreateBridgeSignature(
            _bridger, _user, assetToDeposit, amountToDeposit, assetToDeposit, _userPk, block.timestamp + 1000
        );
        bytes memory permitSignature = _auxCreatePermitSignature(
            IBridger.Permit(_user, address(_bridger), amountToDeposit, _bridger.nonces(_user), block.timestamp + 1000),
            _userPk,
            ERC20Permit(assetToDeposit)
        );
        vm.prank(_owner);
        _bridger.depositBySig(
            kintoWalletL2, sigdata, IBridger.SwapData(address(1), address(1), bytes("")), permitSignature
        );
        assertEq(_bridger.nonces(_user), _bridger.nonces(_user) + 1);
        assertEq(_bridger.deposits(_user, assetToDeposit), amountToDeposit);
    }

    function testDeposit_RevertWhen_CallerIsNotOwnerOrSender() public {
        address assetToDeposit = _bridger.sDAI();
        uint256 amountToDeposit = 1e18;
        deal(address(assetToDeposit), _user, amountToDeposit);
        IBridger.SignatureData memory sigdata = _auxCreateBridgeSignature(
            _bridger, _user, assetToDeposit, amountToDeposit, assetToDeposit, _userPk, block.timestamp + 1000
        );
        vm.startPrank(_user);
        vm.expectRevert(IBridger.OnlySender.selector);
        _bridger.depositBySig(kintoWalletL2, sigdata, IBridger.SwapData(address(1), address(1), bytes("")), bytes(""));
        vm.stopPrank();
    }

    /* ============ Withdraw tests ============ */
}
