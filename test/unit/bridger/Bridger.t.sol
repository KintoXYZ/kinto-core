// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

import "@kinto-core/interfaces/bridger/IBridger.sol";
import "@kinto-core/bridger/Bridger.sol";

import "@kinto-core-test/helpers/WETH.sol";
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
    address internal dai;
    address internal senderAccount;
    address internal connector;
    address internal bridge;
    address internal router;
    address internal weth;
    address internal usde;
    address internal wstEth;

    bytes internal constant EXEC_PAYLOAD = bytes("EXEC_PAYLOAD");
    bytes internal constant OPTIONS = bytes("OPTIONS");

    uint256 internal constant MSG_GAS_LIMIT = 1e6;
    uint256 internal constant GAS_FEE = 1e16;

    address internal kintoWallet;

    BridgerHarness internal bridger;
    IBridger.BridgeData internal mockBridgerData;
    IBridge internal vault;

    ERC20PermitToken internal sDAI;
    ERC20PermitToken internal sUSDe;
    IBridger.BridgeData internal emptyBridgerData;

    function setUp() public override {
        super.setUp();

        kintoWallet = makeAddr("wallet");
        dai = makeAddr("dai");
        senderAccount = makeAddr("sender");
        connector = makeAddr("connector");
        bridge = makeAddr("bridge");
        router = makeAddr("router");
        weth = address(new WETH());
        usde = makeAddr("usde");
        wstEth = makeAddr("wsteth");

        sDAI = new ERC20PermitToken("sDAI", "sDAI");
        sUSDe = new ERC20PermitToken("sUSDe", "sUSDe");

        vault = new BridgeMock();

        // deploy a new Bridger contract
        BridgerHarness implementation =
            new BridgerHarness(router, address(0), address(0), weth, dai, usde, address(sUSDe), wstEth);
        address proxy = address(new UUPSProxy{salt: 0}(address(implementation), ""));
        bridger = BridgerHarness(payable(proxy));
        vm.label(address(bridger), "bridger");

        vm.prank(_owner);
        bridger.initialize(senderAccount);

        mockBridgerData = IBridger.BridgeData({
            vault: address(vault),
            gasFee: GAS_FEE,
            msgGasLimit: MSG_GAS_LIMIT,
            connector: connector,
            execPayload: EXEC_PAYLOAD,
            options: OPTIONS
        });

        vm.etch(address(bridger.PERMIT2()), vm.readFileBinary('./test/data/permit2-bytecode-binary.data'));
    }

    /* ============ depositBySig ============ */

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
            address(vault),
            GAS_FEE,
            abi.encodeCall(
                vault.bridge, (kintoWallet, amountToDeposit, MSG_GAS_LIMIT, connector, EXEC_PAYLOAD, OPTIONS)
            )
        );
        bridger.depositBySig{value: GAS_FEE}(permitSignature, sigdata, bytes(""), mockBridgerData);

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

    /* ============ depositERC20 ============ */

    function testDepositPermit2() public {
        uint256 amountToDeposit = 1e18;
        address assetToDeposit = address(sDAI);
        deal(address(sDAI), _user, amountToDeposit);
        deal(_user, GAS_FEE);
        address PERMIT2 = address(bridger.PERMIT2());

        vm.prank(_user);
        sDAI.approve(PERMIT2, type(uint256).max);

        IBridger.SignatureData memory sigData = _auxCreateBridgeSignature(
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

        IAllowanceTransfer.PermitSingle memory permitSingle =
            IAllowanceTransfer.PermitSingle(IAllowanceTransfer.PermitDetails(address(sDAI), uint160(amountToDeposit), type(uint48).max, 0), address(bridger), type(uint256).max);

        bytes memory permitSignature = _auxPermit2Signature(permitSingle, _userPk, bridger.PERMIT2().DOMAIN_SEPARATOR());

        vm.prank(_owner);
        vm.expectCall(
            address(vault),
            GAS_FEE,
            abi.encodeCall(
                vault.bridge, (kintoWallet, amountToDeposit, MSG_GAS_LIMIT, connector, EXEC_PAYLOAD, OPTIONS)
            )
        );
        bridger.depositPermit2{value: GAS_FEE}(permitSingle, permitSignature, sigData, bytes(""), mockBridgerData);

        assertEq(sDAI.balanceOf(_user), 0);
        assertEq(sDAI.balanceOf(address(bridger)), amountToDeposit);
    }

    /* ============ depositERC20 ============ */

    function testDepositERC20() public {
        uint256 amountToDeposit = 1e18;
        deal(address(sDAI), _user, amountToDeposit);
        deal(_user, GAS_FEE);

        vm.prank(_user);
        sDAI.approve(address(bridger), amountToDeposit);

        vm.prank(_user);
        vm.expectCall(
            address(vault),
            GAS_FEE,
            abi.encodeCall(
                vault.bridge, (kintoWallet, amountToDeposit, MSG_GAS_LIMIT, connector, EXEC_PAYLOAD, OPTIONS)
            )
        );
        bridger.depositERC20{value: GAS_FEE}(
            address(sDAI), amountToDeposit, kintoWallet, address(sDAI), amountToDeposit, bytes(""), mockBridgerData
        );

        assertEq(sDAI.balanceOf(_user), 0);
        assertEq(sDAI.balanceOf(address(bridger)), amountToDeposit);
    }

    /* ============ depositETH ============ */

    function testDepositETH_RevertWhen_AmountIsZero() public {
        uint256 amountToDeposit = 0;
        vm.deal(_user, amountToDeposit);
        vm.startPrank(_owner);
        vm.expectRevert(abi.encodeWithSelector(IBridger.InvalidAmount.selector, amountToDeposit));
        bridger.depositETH{value: amountToDeposit + GAS_FEE}(
            amountToDeposit, kintoWallet, address(sDAI), 1, bytes(""), mockBridgerData
        );
        vm.stopPrank();
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
