// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {stdJson} from "forge-std/StdJson.sol";

import "@kinto-core/interfaces/bridger/IBridger.sol";
import "@kinto-core/bridger/Bridger.sol";

import "@kinto-core-test/fork/const.sol";
import "@kinto-core-test/helpers/UUPSProxy.sol";
import "@kinto-core-test/helpers/SignatureHelper.sol";
import "@kinto-core-test/helpers/SignatureHelper.sol";
import "@kinto-core-test/harness/BridgerHarness.sol";
import "@kinto-core-test/helpers/ArtifactsReader.sol";
import "@kinto-core-test/helpers/BridgeDataHelper.sol";
import {ForkTest} from "@kinto-core-test/helpers/ForkTest.sol";

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

import "@kinto-core/interfaces/bridger/IBridger.sol";
import "@kinto-core/bridger/Bridger.sol";

import "forge-std/console2.sol";

contract BridgerTest is SignatureHelper, ForkTest, ArtifactsReader, BridgeDataHelper {
    using stdJson for string;

    address internal constant kintoWalletL2 = address(33);

    address internal DAI;
    address internal USDC;
    address internal WETH;
    address internal USDe;
    address internal sUSDe;
    address internal ENA;
    address internal wstETH;
    address internal weETH;
    address internal usdmCurvePool;

    BridgerHarness internal bridger;

    uint256 internal amountIn = 1e18;

    function setUp() public override {
        super.setUp();

        upgradeBridger();
    }

    function setUpChain() public virtual override {
        setUpEthereumFork();
    }

    function upgradeBridger() internal {
        vm.deal(_owner, 1e20);

        bridger = BridgerHarness(payable(_getChainDeployment("Bridger")));

        // transfer owner's ownership to _owner
        vm.prank(bridger.owner());
        bridger.transferOwnership(_owner);

        WETH = address(bridger.WETH());
        DAI = bridger.DAI();
        USDe = bridger.USDe();
        sUSDe = bridger.sUSDe();
        wstETH = bridger.wstETH();

        BridgerHarness newImpl = new BridgerHarness(
            EXCHANGE_PROXY,
            block.chainid == ARBITRUM_CHAINID ? USDC_ARBITRUM : address(0),
            WETH,
            DAI,
            USDe,
            sUSDe,
            wstETH
        );
        vm.prank(bridger.owner());
        bridger.upgradeTo(address(newImpl));
    }

    /* ============ Bridger Deposit ============ */

    // deposit wstETH (no swap)
    function testDepositBySig_wstETH_WhenNoSwap() public {
        address asset = bridger.wstETH();
        uint256 amountToDeposit = 1e18;
        IBridger.BridgeData memory data = bridgeData[block.chainid][bridger.wstETH()];
        uint256 bridgerBalanceBefore = ERC20(asset).balanceOf(address(bridger));
        uint256 vaultBalanceBefore = ERC20(asset).balanceOf(address(data.vault));
        deal(asset, _user, amountToDeposit);
        deal(_user, data.gasFee);

        assertEq(ERC20(asset).balanceOf(_user), amountToDeposit);

        IBridger.SignatureData memory sigdata = _auxCreateBridgeSignature(
            kintoWalletL2,
            bridger,
            _user,
            asset,
            asset,
            amountToDeposit,
            amountToDeposit,
            _userPk,
            block.timestamp + 1000
        );
        bytes memory permitSignature = _auxCreatePermitSignature(
            IBridger.Permit(
                _user, address(bridger), amountToDeposit, ERC20Permit(asset).nonces(_user), block.timestamp + 1000
            ),
            _userPk,
            ERC20Permit(asset)
        );

        uint256 nonce = bridger.nonces(_user);
        vm.deal(address(bridger), data.gasFee);
        vm.prank(_owner);
        bridger.depositBySig(permitSignature, sigdata, bytes(""), data);
        assertEq(bridger.nonces(_user), nonce + 1);

        assertEq(ERC20(asset).balanceOf(address(bridger)), bridgerBalanceBefore);
        assertEq(ERC20(asset).balanceOf(address(data.vault)), vaultBalanceBefore + amountToDeposit);
    }

    // USDe to sUSDe
    function testDepositBySig_WhenUSDeTosUSDe() public {
        IBridger.BridgeData memory data = bridgeData[block.chainid][sUSDe];
        address assetToDeposit = bridger.USDe();
        uint256 amountToDeposit = 1e18;
        uint256 sharesBefore = ERC20(sUSDe).balanceOf(address(bridger));
        uint256 vaultSharesBefore = ERC20(sUSDe).balanceOf(address(data.vault));

        deal(assetToDeposit, _user, amountToDeposit);
        deal(_user, data.gasFee);

        assertEq(ERC20(assetToDeposit).balanceOf(_user), amountToDeposit);

        IBridger.SignatureData memory sigdata = _auxCreateBridgeSignature(
            kintoWalletL2, bridger, _user, assetToDeposit, sUSDe, amountToDeposit, 1e17, _userPk, block.timestamp + 1000
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
        vm.deal(address(bridger), data.gasFee);
        vm.prank(_owner);
        bridger.depositBySig(permitSignature, sigdata, bytes(""), data);
        assertEq(bridger.nonces(_user), nonce + 1);

        uint256 shares = ERC4626(sUSDe).previewDeposit(amountToDeposit);
        assertEq(ERC20(sUSDe).balanceOf(address(bridger)), sharesBefore);
        assertEq(ERC20(sUSDe).balanceOf(data.vault), vaultSharesBefore + shares);
    }

    // DAI to wstETH
    function testDepositBySig_WhenSwap_WhenDAItoWstETH() public {
        vm.rollFork(20444390); // block number in which the 0x API data was fetched
        upgradeBridger();

        // top-up _user DAI balance
        IBridger.BridgeData memory data = bridgeData[block.chainid][wstETH];
        address assetIn = DAI;
        address assetOut = wstETH;

        uint256 bridgerAssetInBalanceBefore = ERC20(assetIn).balanceOf(address(bridger));
        uint256 bridgerAssetOutBalanceBefore = ERC20(assetOut).balanceOf(address(bridger));
        uint256 vaultAssetOutBalanceBefore = ERC20(assetOut).balanceOf(data.vault);

        deal(assetIn, _user, amountIn);
        deal(_user, data.gasFee);

        // create a permit signature to allow the bridger to transfer the user's DAI
        bytes memory permitSignature = _auxCreatePermitSignature(
            IBridger.Permit(
                _user, address(bridger), amountIn, ERC20Permit(assetIn).nonces(_user), block.timestamp + 1000
            ),
            _userPk,
            ERC20Permit(assetIn)
        );

        // create a bridge signature to allow the bridger to deposit the user's DAI
        IBridger.SignatureData memory sigdata = _auxCreateBridgeSignature(
            kintoWalletL2,
            bridger,
            _user,
            assetIn,
            bridger.wstETH(),
            amountIn,
            224787412523677,
            _userPk,
            block.timestamp + 1000
        );
        uint256 nonce = bridger.nonces(_user);

        vm.prank(bridger.owner());
        bridger.setBridgeVault(data.vault, true);

        // DAI to wstETH quote's swapData
        // curl 'https://api.0x.org/swap/allowance-holder/quote?chainId=1&sellToken=0x6B175474E89094C44Da98b954EedeAC495271d0F&buyToken=0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0&sellAmount=1000000000000000000&taker=0x0f1b7bd7762662B23486320AA91F30312184f70C' --header '0x-api-key: KEY' | jq > ./test/data/swap-dai-to-wsteth-quote.json
        bytes memory swapCalldata =
            vm.readFile("./test/data/swap-dai-to-wsteth-quote.json").readBytes(".transaction.data");

        vm.deal(address(bridger), data.gasFee);
        vm.prank(bridger.senderAccount());
        bridger.depositBySig(permitSignature, sigdata, swapCalldata, data);

        assertEq(bridger.nonces(_user), nonce + 1);
        // DAI balance should stay the same
        assertEq(ERC20(assetIn).balanceOf(address(bridger)), bridgerAssetInBalanceBefore);
        // wstETH balance should stay the same
        assertEq(ERC20(assetOut).balanceOf(address(bridger)), bridgerAssetOutBalanceBefore);
        // wstETH should be sent to the vault
        assertEq(
            ERC20(assetOut).balanceOf(data.vault),
            vaultAssetOutBalanceBefore + 283975689912282,
            "Invalid Vault assetOut balance"
        );
    }

    // DAI to wUSDM
    function testDepositBySig_WhenDaiToWUSDM() public {
        setUpArbitrumFork();
        vm.rollFork(257064127); // block number in which the 0x API data was fetched
        upgradeBridger();

        IBridger.BridgeData memory data = bridgeData[block.chainid][wUSDM];
        address assetToDeposit = DAI_ARBITRUM;
        uint256 amountToDeposit = 1e18;
        uint256 sharesBefore = ERC20(wUSDM).balanceOf(address(bridger));
        uint256 vaultSharesBefore = ERC20(wUSDM).balanceOf(address(data.vault));

        deal(assetToDeposit, _user, amountToDeposit);
        deal(_user, data.gasFee);

        assertEq(ERC20(assetToDeposit).balanceOf(_user), amountToDeposit);

        IBridger.SignatureData memory sigdata = _auxCreateBridgeSignature(
            kintoWalletL2,
            bridger,
            _user,
            assetToDeposit,
            wUSDM,
            amountToDeposit,
            968e3,
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

        vm.prank(bridger.owner());
        bridger.setBridgeVault(data.vault, true);

        // DAI to USDM quote's swapData
        // curl 'https://api.0x.org/swap/allowance-holder/quote?chainId=42161&buyToken=0x59D9356E565Ab3A36dD77763Fc0d87fEaf85508C&sellToken=0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1&sellAmount=1000000000000000000&taker=0xb7DfE09Cf3950141DFb7DB8ABca90dDef8d06Ec0' -H '0x-api-key: key' -H '0x-version: v2' | jq > ./test/data/swap-dai-to-usdm-arb.json
        bytes memory swapCalldata = vm.readFile("./test/data/swap-dai-to-usdm-arb.json").readBytes(".transaction.data");

        vm.deal(address(bridger), data.gasFee);
        vm.prank(_owner);
        bridger.depositBySig(permitSignature, sigdata, swapCalldata, data);
        assertEq(bridger.nonces(_user), nonce + 1);

        uint256 shares = ERC4626(wUSDM).previewDeposit(999994255037510828);
        assertEq(ERC20(wUSDM).balanceOf(address(bridger)), sharesBefore, "Invalid balance of the Bridger");
        assertEq(ERC20(wUSDM).balanceOf(data.vault), vaultSharesBefore + shares, "Invalid balance of the Vault");
    }

    // ETH to wUSDM
    function testDepositETH_WhenEthToWUSDM() public {
        setUpArbitrumFork();
        vm.rollFork(257072953); // block number in which the 0x API data was fetched
        upgradeBridger();

        IBridger.BridgeData memory data = bridgeData[block.chainid][wUSDM];
        uint256 amountToDeposit = 1e18;
        uint256 sharesBefore = ERC20(wUSDM).balanceOf(address(bridger));
        uint256 vaultSharesBefore = ERC20(wUSDM).balanceOf(address(data.vault));

        deal(_user, amountToDeposit);
        deal(_user, data.gasFee);

        vm.prank(bridger.owner());
        bridger.setBridgeVault(data.vault, true);

        // ETH to USDM quote's swapData
        // curl 'https://api.0x.org/swap/allowance-holder/quote?chainId=42161&buyToken=0x59D9356E565Ab3A36dD77763Fc0d87fEaf85508C&sellToken=0x82aF49447D8a07e3bd95BD0d56f35241523fBab1&sellAmount=1000000000000000000&taker=0xb7DfE09Cf3950141DFb7DB8ABca90dDef8d06Ec0' -H '0x-api-key: key' -H '0x-version: v2' | jq > ./test/data/swap-weth-to-usdm-arb.json
        bytes memory swapCalldata = vm.readFile("./test/data/swap-weth-to-usdm-arb.json").readBytes(".transaction.data");

        vm.prank(_owner);
        bridger.depositETH{value: amountToDeposit + data.gasFee}(
            amountToDeposit, kintoWalletL2, wUSDM, 251959574561240729584, swapCalldata, data
        );

        uint256 shares = ERC4626(wUSDM).previewDeposit(264112831900159671031);
        assertEq(ERC20(wUSDM).balanceOf(address(bridger)), sharesBefore, "Invalid balance of the Bridger");
        assertEq(ERC20(wUSDM).balanceOf(data.vault), vaultSharesBefore + shares, "Invalid balance of the Vault");
    }

    // wUSDM to WETH
    function testDepositERC20_WhenWusdmToWeth() public {
        setUpArbitrumFork();
        vm.rollFork(257328223); // block number in which the 0x API data was fetched
        upgradeBridger();

        IBridger.BridgeData memory data = bridgeData[block.chainid][WETH_ARBITRUM];
        address assetToDeposit = wUSDM;
        uint256 amountToDeposit = 1e18;
        uint256 balanceBefore = ERC20(WETH_ARBITRUM).balanceOf(address(bridger));
        uint256 vaultBalanceBefore = ERC20(WETH_ARBITRUM).balanceOf(address(data.vault));

        deal(assetToDeposit, _user, amountToDeposit);
        deal(_user, data.gasFee);

        // USDM to WETH quote's swapData
        bytes memory swapCalldata = vm.readFile("./test/data/swap-usmd-to-weth-arb.json").readBytes(".transaction.data");

        uint256 amountOut = 406379773601548;

        vm.prank(_user);
        IERC20(assetToDeposit).approve(address(bridger), amountToDeposit);

        vm.prank(bridger.owner());
        bridger.setBridgeVault(data.vault, true);

        vm.deal(address(bridger), data.gasFee);
        vm.prank(_user);
        bridger.depositERC20(
            assetToDeposit, amountToDeposit, kintoWalletL2, WETH_ARBITRUM, amountOut, swapCalldata, data
        );

        assertEq(ERC20(WETH_ARBITRUM).balanceOf(address(bridger)), balanceBefore, "Invalid balance of the Bridger");
        assertEq(
            ERC20(WETH_ARBITRUM).balanceOf(data.vault), vaultBalanceBefore + amountOut, "Invalid balance of the Vault"
        );
    }

    // ETH to stUSD
    function testDepositETH_WhenEthToStUSD() public {
        setUpArbitrumFork();
        vm.rollFork(238827860); // block number in which the 0x API data was fetched
        upgradeBridger();

        IBridger.BridgeData memory data = bridgeData[block.chainid][stUSD];
        uint256 amountToDeposit = 1e18;
        uint256 sharesBefore = ERC20(stUSD).balanceOf(address(bridger));
        uint256 vaultSharesBefore = ERC20(stUSD).balanceOf(address(data.vault));

        deal(_user, amountToDeposit);
        deal(_user, data.gasFee);

        vm.prank(bridger.owner());
        bridger.setBridgeVault(data.vault, true);

        // ETH to USDC quote's swapData
        // curl 'https://api.0x.org/swap/allowance-holder/quote?chainId=42161&buyToken=0xaf88d065e77c8cC2239327C5EDb3A432268e5831&sellToken=0x82aF49447D8a07e3bd95BD0d56f35241523fBab1&sellAmount=1000000000000000000&taker=0xb7DfE09Cf3950141DFb7DB8ABca90dDef8d06Ec0' --header '0x-api-key: key' | jq > ./test/data/swap-weth-to-usdc-arb.json
        bytes memory swapCalldata = vm.readFile("./test/data/swap-weth-to-usdc-arb.json").readBytes(".transaction.data");

        vm.prank(_owner);
        bridger.depositETH{value: amountToDeposit + data.gasFee}(
            amountToDeposit, kintoWalletL2, stUSD, 2861397724198764848285, swapCalldata, data
        );

        uint256 shares = ERC4626(stUSD).previewDeposit(2993214711000000000000);
        assertEq(ERC20(stUSD).balanceOf(address(bridger)), sharesBefore, "Invalid balance of the Bridger");
        assertEq(ERC20(stUSD).balanceOf(data.vault), vaultSharesBefore + shares, "Invalid balance of the Vault");
    }

    // USDC to SolvBTC
    function testDepositERC20_WhenUsdcToSolvBtc() public {
        setUpArbitrumFork();
        vm.rollFork(244906436); // block number in which the 0x API data was fetched
        upgradeBridger();

        IBridger.BridgeData memory data = bridgeData[block.chainid][SOLV_BTC_ARBITRUM];
        address assetToDeposit = USDC_ARBITRUM;
        uint256 amountToDeposit = 1e6;
        uint256 solvBtcBalanceBefore = ERC20(SOLV_BTC_ARBITRUM).balanceOf(address(bridger));
        uint256 vaultSolvBtcBalanceBefore = ERC20(SOLV_BTC_ARBITRUM).balanceOf(address(data.vault));

        deal(assetToDeposit, _user, amountToDeposit);
        deal(_user, data.gasFee);

        // USDC to WBTC quote's swapData
        // curl 'https://api.0x.org/swap/allowance-holder/quote?chainId=42161&buyToken=0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f&sellToken=0xaf88d065e77c8cC2239327C5EDb3A432268e5831&sellAmount=1000000&taker=0xb7DfE09Cf3950141DFb7DB8ABca90dDef8d06Ec0' --header '0x-api-key: key' | jq > ./test/data/swap-usdc-to-wbtc-arb.json
        bytes memory swapCalldata = vm.readFile("./test/data/swap-usdc-to-wbtc-arb.json").readBytes(".transaction.data");

        uint256 amountOut = 1692e10;

        vm.prank(_user);
        IERC20(assetToDeposit).approve(address(bridger), amountToDeposit);

        vm.prank(bridger.owner());
        bridger.setBridgeVault(data.vault, true);

        vm.deal(address(bridger), data.gasFee);
        vm.prank(_user);
        bridger.depositERC20(
            assetToDeposit, amountToDeposit, kintoWalletL2, SOLV_BTC_ARBITRUM, amountOut, swapCalldata, data
        );

        assertEq(
            ERC20(SOLV_BTC_ARBITRUM).balanceOf(address(bridger)), solvBtcBalanceBefore, "Invalid balance of the Bridger"
        );
        assertEq(
            ERC20(SOLV_BTC_ARBITRUM).balanceOf(data.vault),
            vaultSolvBtcBalanceBefore + amountOut,
            "Invalid balance of the Vault"
        );
    }

    // WBTC to SolvBTC
    function testDepositERC20_WhenWBtcToSolvBtc() public {
        setUpArbitrumFork();
        vm.rollFork(244906436);
        upgradeBridger();

        IBridger.BridgeData memory data = bridgeData[block.chainid][SOLV_BTC_ARBITRUM];
        address assetToDeposit = WBTC_ARBITRUM;
        uint256 amountToDeposit = 1e8;
        uint256 solvBtcBalanceBefore = ERC20(SOLV_BTC_ARBITRUM).balanceOf(address(bridger));
        uint256 vaultSolvBtcBalanceBefore = ERC20(SOLV_BTC_ARBITRUM).balanceOf(address(data.vault));

        deal(assetToDeposit, _user, amountToDeposit);
        deal(_user, data.gasFee);

        vm.prank(_user);
        IERC20(assetToDeposit).approve(address(bridger), amountToDeposit);

        vm.prank(bridger.owner());
        bridger.setBridgeVault(data.vault, true);

        vm.deal(address(bridger), data.gasFee);
        vm.prank(_user);
        bridger.depositERC20(
            assetToDeposit, amountToDeposit, kintoWalletL2, SOLV_BTC_ARBITRUM, amountToDeposit * 1e10, bytes(""), data
        );

        assertEq(
            ERC20(SOLV_BTC_ARBITRUM).balanceOf(address(bridger)), solvBtcBalanceBefore, "Invalid balance of the Bridger"
        );
        assertEq(
            ERC20(SOLV_BTC_ARBITRUM).balanceOf(data.vault),
            vaultSolvBtcBalanceBefore + amountToDeposit * 1e10,
            "Invalid balance of the Vault"
        );
    }

    // SolvBTC to SolvBTC
    function testDepositERC20_WhenSolvBtcToDai() public {
        // not possible due to SolvBTC redemption taking more than one tx to transfer WBTC
        vm.skip(true);
        setUpArbitrumFork();
        vm.rollFork(257028313);
        upgradeBridger();

        IBridger.BridgeData memory data = bridgeData[block.chainid][DAI_ARBITRUM];
        address assetToDeposit = SOLV_BTC_ARBITRUM;
        uint256 amountToDeposit = 1e18;
        uint256 bridgerBalanceBefore = ERC20(DAI_ARBITRUM).balanceOf(address(bridger));
        uint256 vaultBalanceBefore = ERC20(DAI_ARBITRUM).balanceOf(address(data.vault));

        deal(assetToDeposit, _user, amountToDeposit);
        deal(_user, data.gasFee);

        // WBTC to DAI quote's swapData
        // curl 'https://api.0x.org/swap/allowance-holder/quote?chainId=42161&buyToken=0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f&sellToken=0xaf88d065e77c8cC2239327C5EDb3A432268e5831&sellAmount=1000000&taker=0xb7DfE09Cf3950141DFb7DB8ABca90dDef8d06Ec0' --header '0x-api-key: key' | jq > ./test/data/swap-wbtc-to-dai-arb.json
        bytes memory swapCalldata = vm.readFile("./test/data/swap-wbtc-to-dai-arb.json").readBytes(".transaction.data");

        vm.prank(_user);
        IERC20(assetToDeposit).approve(address(bridger), amountToDeposit);

        vm.prank(bridger.owner());
        bridger.setBridgeVault(data.vault, true);

        vm.deal(address(bridger), data.gasFee);
        vm.prank(_user);
        bridger.depositERC20(assetToDeposit, amountToDeposit, kintoWalletL2, DAI_ARBITRUM, 0, swapCalldata, data);

        assertEq(
            ERC20(DAI_ARBITRUM).balanceOf(address(bridger)), bridgerBalanceBefore, "Invalid balance of the Bridger"
        );
        assertEq(
            ERC20(DAI_ARBITRUM).balanceOf(data.vault),
            vaultBalanceBefore + amountToDeposit,
            "Invalid balance of the Vault"
        );
    }

    // SolvBTC to SolvBTC
    function testDepositERC20_WhenSolvBtcToSolvBtc() public {
        setUpArbitrumFork();
        vm.rollFork(244906436);
        upgradeBridger();

        IBridger.BridgeData memory data = bridgeData[block.chainid][SOLV_BTC_ARBITRUM];
        address assetToDeposit = SOLV_BTC_ARBITRUM;
        uint256 amountToDeposit = 1e18;
        uint256 solvBtcBalanceBefore = ERC20(SOLV_BTC_ARBITRUM).balanceOf(address(bridger));
        uint256 vaultSolvBtcBalanceBefore = ERC20(SOLV_BTC_ARBITRUM).balanceOf(address(data.vault));

        deal(assetToDeposit, _user, amountToDeposit);
        deal(_user, data.gasFee);

        vm.prank(_user);
        IERC20(assetToDeposit).approve(address(bridger), amountToDeposit);

        vm.prank(bridger.owner());
        bridger.setBridgeVault(data.vault, true);

        vm.deal(address(bridger), data.gasFee);
        vm.prank(_user);
        bridger.depositERC20(
            assetToDeposit, amountToDeposit, kintoWalletL2, SOLV_BTC_ARBITRUM, amountToDeposit, bytes(""), data
        );

        assertEq(
            ERC20(SOLV_BTC_ARBITRUM).balanceOf(address(bridger)), solvBtcBalanceBefore, "Invalid balance of the Bridger"
        );
        assertEq(
            ERC20(SOLV_BTC_ARBITRUM).balanceOf(data.vault),
            vaultSolvBtcBalanceBefore + amountToDeposit,
            "Invalid balance of the Vault"
        );
    }

    /* ============ Bridger ETH Deposit ============ */

    function testDepositETH() public {
        uint256 amountToDeposit = 1e18;
        IBridger.BridgeData memory data = bridgeData[block.chainid][bridger.wstETH()];
        uint256 balanceBefore = ERC20(bridger.wstETH()).balanceOf(data.vault);
        vm.deal(_user, amountToDeposit + data.gasFee);

        vm.startPrank(_user);
        bridger.depositETH{value: amountToDeposit + data.gasFee}(
            amountToDeposit, kintoWalletL2, bridger.wstETH(), 1e17, bytes(""), data
        );
        vm.stopPrank();

        assertEq(bridger.nonces(_user), 0);
        uint256 balance = ERC20(bridger.wstETH()).balanceOf(data.vault);
        assertTrue(balance - balanceBefore > 0);
    }

    function testDepositETH_WhenSwapEthTosDai() public {
        vm.rollFork(20443534); // block number in which the 0x API data was fetched
        upgradeBridger();

        address assetOut = sDAI_ETHEREUM;

        IBridger.BridgeData memory data = bridgeData[block.chainid][sDAI_ETHEREUM];
        amountIn = 1 ether;
        // top-up `_user` ETH balance
        vm.deal(_user, amountIn + data.gasFee);

        vm.prank(bridger.owner());
        bridger.setBridgeVault(data.vault, true);

        // WETH to sDAI quote's swapData
        // curl 'https://api.0x.org/swap/allowance-holder/quote?chainId=1&sellToken=0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2&buyToken=0x83F20F44975D03b1b09e64809B757c47f942BEeA&sellAmount=1000000000000000000&taker=0x0f1b7bd7762662B23486320AA91F30312184f70C' --header '0x-api-key: KEY' | jq > ./test/data/swap-eth-to-sdai-quote.json
        bytes memory swapCalldata =
            vm.readFile("./test/data/swap-eth-to-sdai-quote.json").readBytes(".transaction.data");

        uint256 bridgerBalanceBefore = address(bridger).balance;
        uint256 vaultAssetOutBalanceBefore = ERC20(assetOut).balanceOf(data.vault);
        uint256 amountOut = 2456783777720327644276;

        vm.prank(_user);
        bridger.depositETH{value: amountIn + data.gasFee}(
            amountIn, kintoWalletL2, assetOut, amountOut, swapCalldata, data
        );

        assertEq(_user.balance, 0, "User balance should be zero");
        assertEq(address(bridger).balance, bridgerBalanceBefore); // there's no ETH since it was swapped
        // sDai should be sent to the vault
        assertEq(
            ERC20(assetOut).balanceOf(data.vault),
            vaultAssetOutBalanceBefore + amountOut,
            "Invalid Vault assetOut balance"
        );
    }

    function testDepositETH_WhenSwapEthToSolveBtc() public {
        setUpArbitrumFork();
        vm.rollFork(244948289); // block number in which the 0x API data was fetched
        upgradeBridger();

        address assetOut = SOLV_BTC_ARBITRUM;

        IBridger.BridgeData memory data = bridgeData[block.chainid][SOLV_BTC_ARBITRUM];
        amountIn = 1 ether;
        // top-up `_user` ETH balance
        vm.deal(_user, amountIn + data.gasFee);

        // WETH to WBTC quote's swapData
        // curl 'https://api.0x.org/swap/allowance-holder/quote?chainId=42161&buyToken=0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f&sellToken=0x82aF49447D8a07e3bd95BD0d56f35241523fBab1&sellAmount=1000000000000000000&taker=0xb7DfE09Cf3950141DFb7DB8ABca90dDef8d06Ec0' --header '0x-api-key: key' | jq > ./test/data/swap-weth-to-wbtc-arb.json
        bytes memory swapCalldata = vm.readFile("./test/data/swap-weth-to-wbtc-arb.json").readBytes(".transaction.data");

        uint256 bridgerBalanceBefore = address(bridger).balance;
        uint256 vaultAssetOutBalanceBefore = ERC20(assetOut).balanceOf(data.vault);
        uint256 amountOut = 43787900000000000;

        vm.prank(bridger.owner());
        bridger.setBridgeVault(data.vault, true);

        vm.prank(_user);
        bridger.depositETH{value: amountIn + data.gasFee}(
            amountIn, kintoWalletL2, assetOut, amountOut, swapCalldata, data
        );

        assertEq(_user.balance, 0, "User balance should be zero");
        assertEq(address(bridger).balance, bridgerBalanceBefore); // there's no ETH since it was swapped
        // solvBTC should be sent to the vault
        assertEq(
            ERC20(assetOut).balanceOf(data.vault),
            vaultAssetOutBalanceBefore + amountOut,
            "Invalid Vault assetOut balance"
        );
    }
}
