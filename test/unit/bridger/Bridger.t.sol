// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

import "@kinto-core/interfaces/bridger/IBridger.sol";
import "@kinto-core/bridger/Bridger.sol";

import "@kinto-core-test/helpers/UUPSProxy.sol";
import "@kinto-core-test/helpers/SignatureHelper.sol";
import "@kinto-core-test/helpers/SignatureHelper.sol";
import "@kinto-core-test/harness/BridgerHarness.sol";
import "@kinto-core-test/mock/BridgeMock.sol";
import "@kinto-core-test/SharedSetup.t.sol";

contract ERC20PermitToken is ERC20, ERC20Permit {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) ERC20Permit(name) {}
}

contract BridgerTest is SignatureHelper, SharedSetup {
    address internal constant DAI = address(1);
    address internal constant SENDER_ACCOUNT = address(5);
    address internal constant CONNECTOR = address(6);
    address internal constant L2_VAULT = address(7);
    address internal constant BRIDGE = address(8);
    address internal constant ROUTER = address(9);
    address internal constant wETH = address(10);
    address internal constant USDe = address(11);
    address internal constant sUSDe = address(12);
    address internal constant wstETH = address(13);

    bytes internal constant EXEC_PAYLOAD = bytes("EXEC_PAYLOAD");
    bytes internal constant OPTIONS = bytes("OPTIONS ");

    uint256 internal constant MSG_GAS_LIMIT = 1e6;

    address internal kintoWallet;

    BridgerHarness internal bridger;
    IBridger.BridgeData internal mockBridgerData;
    IBridge internal bridgeMock;

    ERC20PermitToken internal sDAI;

    function setUp() public override {
        super.setUp();

        kintoWallet = address(1);

        sDAI = new ERC20PermitToken("sDAI", "sDAI");

        bridgeMock = new BridgeMock();

        // deploy a new Bridger contract
        BridgerHarness implementation =
            new BridgerHarness(L2_VAULT, address(bridgeMock), ROUTER, wETH, DAI, USDe, sUSDe, wstETH);
        address proxy = address(new UUPSProxy{salt: 0}(address(implementation), ""));
        bridger = BridgerHarness(payable(proxy));

        vm.prank(_owner);
        bridger.initialize(SENDER_ACCOUNT);

        address[] memory assets = new address[](1);
        assets[0] = address(sDAI);
        bool[] memory flags = new bool[](1);
        flags[0] = true;
        vm.prank(_owner);
        bridger.whitelistFinalAssets(assets, flags);

        mockBridgerData = IBridger.BridgeData({
            msgGasLimit: MSG_GAS_LIMIT,
            connector: CONNECTOR,
            execPayload: EXEC_PAYLOAD,
            options: OPTIONS
        });
    }

    /* ============ Bridger Deposit ============ */

    // deposit sDAI (no swap)
    function testDepositBySig_sDAI_WhenNoSwap() public {
        address assetToDeposit = address(sDAI);
        uint256 amountToDeposit = 1e18;
        uint256 balanceBefore = ERC20(assetToDeposit).balanceOf(address(bridger));
        deal(assetToDeposit, _user, amountToDeposit);

        assertEq(ERC20(assetToDeposit).balanceOf(_user), amountToDeposit);

        IBridger.SignatureData memory sigdata = _auxCreateBridgeSignature(
            kintoWallet,
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

        vm.expectCall(
            address(bridgeMock),
            abi.encodeCall(
                bridgeMock.bridge, (kintoWallet, amountToDeposit, MSG_GAS_LIMIT, CONNECTOR, EXEC_PAYLOAD, OPTIONS)
            )
        );
        bridger.depositBySig(permitSignature, sigdata, bytes(""), mockBridgerData);

        assertEq(bridger.nonces(_user), nonce + 1);
        assertEq(ERC20(assetToDeposit).balanceOf(address(bridger)), balanceBefore + amountToDeposit);
    }

    function testDepositBySig_RevertWhen_CallerIsNotOwnerOrSender() public {
        address assetToDeposit = address(sDAI);
        uint256 amountToDeposit = 1e18;
        deal(address(assetToDeposit), _user, amountToDeposit);

        IBridger.SignatureData memory sigdata = _auxCreateBridgeSignature(
            kintoWallet,
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
        bridger.depositBySig(bytes(""), sigdata, bytes(""), mockBridgerData);
    }

    function testDepositBySig_RevertWhen_AmountIsZero() public {
        address assetToDeposit = address(sDAI);
        uint256 amountToDeposit = 0;
        deal(address(assetToDeposit), _user, amountToDeposit);

        IBridger.SignatureData memory sigdata = _auxCreateBridgeSignature(
            kintoWallet,
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
        vm.expectRevert(abi.encodeWithSelector(IBridger.InvalidAmount.selector, uint256(0)));
        vm.prank(_owner);
        bridger.depositBySig(permitSignature, sigdata, bytes(""), mockBridgerData);
    }

    /* ============ Bridger ETH Deposit ============ */

    function testDepositETH_RevertWhen_FinalAssetisNotAllowed() public {
        uint256 amountToDeposit = 1e18;
        vm.deal(_user, amountToDeposit);
        vm.startPrank(_owner);
        vm.expectRevert(abi.encodeWithSelector(IBridger.InvalidFinalAsset.selector, address(1)));
        bridger.depositETH{value: amountToDeposit}(kintoWallet, address(1), 1, bytes(""), mockBridgerData);
        vm.stopPrank();
    }

    function testDepositETH_RevertWhen_AmountIsZero() public {
        uint256 amountToDeposit = 0;
        vm.deal(_user, amountToDeposit);
        vm.startPrank(_owner);
        vm.expectRevert(abi.encodeWithSelector(IBridger.InvalidAmount.selector, amountToDeposit));
        bridger.depositETH{value: amountToDeposit}(kintoWallet, address(sDAI), 1, bytes(""), mockBridgerData);
        vm.stopPrank();
    }

    /* ============ Bridge Deposits ============ */

    function testBridgeDeposits() public {
        uint256 amountToDeposit = 1e18;
        deal(address(sDAI), address(bridger), amountToDeposit);

        vm.prank(_owner);
        vm.expectCall(
            address(bridgeMock),
            abi.encodeCall(
                bridgeMock.bridge, (L2_VAULT, amountToDeposit, MSG_GAS_LIMIT, CONNECTOR, EXEC_PAYLOAD, OPTIONS)
            )
        );
        bridger.bridgeDeposits(address(sDAI), mockBridgerData);
    }

    function testBridgeDeposits_RevertWhen_NotOwner() public {
        vm.expectRevert(IBridger.OnlyOwner.selector);
        bridger.bridgeDeposits(address(sDAI), mockBridgerData);
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

    function testWhitelistFinalAsset() public {
        address asset = address(768);
        address[] memory assets = new address[](1);
        assets[0] = asset;
        bool[] memory flags = new bool[](1);
        flags[0] = true;
        vm.prank(_owner);
        bridger.whitelistFinalAssets(assets, flags);
        assertEq(bridger.finalAllowedAssets(asset), true);
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

    function testSetSenderAccount_RevertWhen_NotOwner() public {
        vm.expectRevert("Ownable: caller is not the owner");
        bridger.setSenderAccount(address(0xdead));
    }

    /* ============ EIP712 ============ */

    function testDomainSeparatorV4() public view {
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
        address wallet,
        address signer,
        address inputAsset,
        address finalAsset,
        uint256 amount,
        uint256 minReceive,
        uint256 nonce,
        uint256 expiresAt,
        bytes calldata signature
    ) public view {
        IBridger.SignatureData memory data = IBridger.SignatureData({
            kintoWallet: wallet,
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
                    wallet,
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
