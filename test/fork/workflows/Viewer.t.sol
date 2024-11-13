// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {stdJson} from "forge-std/StdJson.sol";

import "@kinto-core/interfaces/bridger/IBridger.sol";
import {IAccessRegistry} from "@kinto-core/interfaces/IAccessRegistry.sol";
import {IAccessPoint} from "@kinto-core/interfaces/IAccessPoint.sol";
import {Viewer} from "@kinto-core/viewers/Viewer.sol";

import {AccessRegistry} from "@kinto-core/access/AccessRegistry.sol";
import {AaveLendWorkflow} from "@kinto-core/access/workflows/AaveLendWorkflow.sol";
import {AaveBorrowWorkflow} from "@kinto-core/access/workflows/AaveBorrowWorkflow.sol";

import "@kinto-core-test/fork/const.sol";
import "@kinto-core-test/helpers/UUPSProxy.sol";
import "@kinto-core-test/helpers/SignatureHelper.sol";
import "@kinto-core-test/helpers/ArtifactsReader.sol";
import {ForkTest} from "@kinto-core-test/helpers/ForkTest.sol";
import {SharedSetup} from "@kinto-core-test/SharedSetup.t.sol";
import {IAavePool, IPoolAddressesProvider} from "@kinto-core/interfaces/external/IAavePool.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "forge-std/console2.sol";

contract ViewerTest is SignatureHelper, ForkTest, ArtifactsReader, Constants {
    using stdJson for string;

    AccessRegistry internal accessRegistry;
    IAccessPoint internal accessPoint;
    AaveLendWorkflow internal aaveLendWorkflow;
    AaveBorrowWorkflow internal aaveBorrowWorkflow;
    IAavePool internal aavePool;
    Viewer internal viewer;

    function setUp() public override {
        super.setUp();

        accessRegistry = AccessRegistry(_getChainDeployment("AccessRegistry"));
        aavePool = IAavePool(IPoolAddressesProvider(ARB_AAVE_POOL_PROVIDER).getPool());

        deploy();
    }

    function deploy() internal {
        // Deploy access point for test user
        accessPoint = accessRegistry.deployFor(address(alice0));
        vm.label(address(accessPoint), "accessPoint");

        // Deploy Viewer contract
        viewer = new Viewer(ARB_AAVE_POOL_PROVIDER, address(accessRegistry));
        UUPSProxy proxy = new UUPSProxy(address(viewer), "");
        viewer = Viewer(address(proxy));
        viewer.initialize();
        vm.label(address(viewer), "viewer");

        // Deploy and allow workflows
        aaveLendWorkflow = new AaveLendWorkflow(ARB_AAVE_POOL_PROVIDER);
        aaveBorrowWorkflow = new AaveBorrowWorkflow(ARB_AAVE_POOL_PROVIDER);
        vm.label(address(aaveLendWorkflow), "aaveLendWorkflow");
        vm.label(address(aaveBorrowWorkflow), "aaveBorrowWorkflow");

        vm.startPrank(accessRegistry.owner());
        accessRegistry.allowWorkflow(address(aaveLendWorkflow));
        accessRegistry.allowWorkflow(address(aaveBorrowWorkflow));
        vm.stopPrank();
    }

    function setUpChain() public virtual override {
        setUpArbitrumFork();
        vm.rollFork(273472816);
    }

    function testGetAccountData_BeforeLending() public {
        address[] memory assets = new address[](1);
        assets[0] = USDC_ARBITRUM;

        Viewer.AccountData memory data = viewer.getAccountData(assets, alice0);

        // Verify account data initialized to zero
        assertEq(data.aaveTotalCollateralBase, 0, "Initial collateral should be 0");
        assertEq(data.aaveTotalDebtBase, 0, "Initial debt should be 0");
        assertEq(data.aaveHealthFactor, type(uint256).max, "Initial health factor should be max");

        // Verify asset data
        assertEq(data.assets[0].aaveSupplyAmount, 0, "Initial supply amount should be 0");
        assertEq(data.assets[0].aaveBorrowAmount, 0, "Initial borrow amount should be 0");
        assertEq(data.assets[0].tokenBalance, 0, "Initial token balance should be 0");
        assertEq(data.assets[0].aTokenBalance, 0, "Initial aToken balance should be 0");

        // Verify market data exists
        assertTrue(data.assets[0].aaveSupplyAPY > 0, "Supply APY should be non-zero");
        assertTrue(data.assets[0].aaveBorrowAPY > 0, "Borrow APY should be non-zero");
        assertTrue(data.assets[0].aaveSupplyCapacity > 0, "Supply capacity should be non-zero");
        assertTrue(data.assets[0].aaveBorrowCapacity > 0, "Borrow capacity should be non-zero");
    }

    function testGetAccountData_AfterLending() public {
        address assetToLend = USDC_ARBITRUM;
        uint256 amountToLend = 1e6;

        // Setup test arrays
        address[] memory assets = new address[](1);
        assets[0] = assetToLend;

        // Get initial data
        Viewer.AccountData memory initialData = viewer.getAccountData(assets, alice0);

        // Fund and execute lend
        deal(assetToLend, address(accessPoint), amountToLend);
        bytes memory workflowData = abi.encodeWithSelector(AaveLendWorkflow.lend.selector, assetToLend, amountToLend);
        vm.prank(alice0);
        accessPoint.execute(address(aaveLendWorkflow), workflowData);

        // Get updated data
        Viewer.AccountData memory finalData = viewer.getAccountData(assets, alice0);

        // Verify account data changed
        assertTrue(
            finalData.aaveTotalCollateralBase > initialData.aaveTotalCollateralBase, "Collateral should increase"
        );
        assertEq(finalData.aaveTotalDebtBase, 0, "Debt should remain 0");
        assertEq(finalData.aaveHealthFactor, type(uint256).max, "Health factor should be max with no debt");

        // Verify asset data changed
        assertEq(finalData.assets[0].aaveSupplyAmount, amountToLend, "Supply amount should match lent amount");
        assertEq(finalData.assets[0].aaveBorrowAmount, 0, "Borrow amount should remain 0");
        assertEq(finalData.assets[0].tokenBalance, 0, "Token balance should be 0 after lending");
        assertEq(finalData.assets[0].aTokenBalance, amountToLend, "aToken balance should match lent amount");

        // Market data should remain similar
        assertTrue(finalData.assets[0].aaveSupplyAPY > 0, "Supply APY should still be non-zero");
        assertTrue(finalData.assets[0].aaveBorrowAPY > 0, "Borrow APY should still be non-zero");
    }

    function testGetAccountData_MultipleAssets() public {
        // Setup test with USDC and USDT
        address[] memory assets = new address[](2);
        assets[0] = USDC_ARBITRUM;
        assets[1] = USDT_ARBITRUM;
        uint256 amountToLend = 1e6;

        // Fund both assets
        deal(assets[0], address(accessPoint), amountToLend);
        deal(assets[1], address(accessPoint), amountToLend);

        // Lend both assets
        for (uint256 i = 0; i < assets.length; i++) {
            bytes memory workflowData = abi.encodeWithSelector(AaveLendWorkflow.lend.selector, assets[i], amountToLend);
            vm.prank(alice0);
            accessPoint.execute(address(aaveLendWorkflow), workflowData);
        }

        // Get account data
        Viewer.AccountData memory data = viewer.getAccountData(assets, alice0);

        // Verify account data
        assertTrue(data.aaveTotalCollateralBase > 0, "Should have collateral");
        assertEq(data.aaveTotalDebtBase, 0, "Should have no debt");
        assertEq(data.aaveHealthFactor, type(uint256).max, "Should have max health factor");

        // Verify both assets
        for (uint256 i = 0; i < assets.length; i++) {
            assertEq(data.assets[i].aaveSupplyAmount, amountToLend, "Supply amount should match lent amount");
            assertEq(data.assets[i].aaveBorrowAmount, 0, "Borrow amount should be 0");
            assertEq(data.assets[i].tokenBalance, 0, "Token balance should be 0");
            assertEq(data.assets[i].aTokenBalance, amountToLend, "aToken balance should match lent amount");
            assertTrue(data.assets[i].aaveSupplyAPY > 0, "Supply APY should be non-zero");
            assertTrue(data.assets[i].aaveBorrowAPY > 0, "Borrow APY should be non-zero");
        }
    }

    function testGetAccountData_AfterBorrowing() public {
        address collateralAsset = USDC_ARBITRUM;
        address borrowAsset = USDT_ARBITRUM;
        uint256 collateralAmount = 1000e6; // 1000 USDC
        uint256 borrowAmount = 500e6; // 500 USDT

        // Setup test arrays
        address[] memory assets = new address[](2);
        assets[0] = collateralAsset;
        assets[1] = borrowAsset;

        // Get initial data
        Viewer.AccountData memory initialData = viewer.getAccountData(assets, alice0);

        // Supply collateral
        deal(collateralAsset, address(accessPoint), collateralAmount);
        bytes memory lendData =
            abi.encodeWithSelector(AaveLendWorkflow.lend.selector, collateralAsset, collateralAmount);
        vm.prank(alice0);
        accessPoint.execute(address(aaveLendWorkflow), lendData);

        // Borrow against collateral
        bytes memory borrowData = abi.encodeWithSelector(AaveBorrowWorkflow.borrow.selector, borrowAsset, borrowAmount);
        vm.prank(alice0);
        accessPoint.execute(address(aaveBorrowWorkflow), borrowData);

        // Get final data
        Viewer.AccountData memory finalData = viewer.getAccountData(assets, alice0);

        // Verify account metrics changed
        assertTrue(
            finalData.aaveTotalCollateralBase > initialData.aaveTotalCollateralBase, "Collateral should increase"
        );
        assertTrue(finalData.aaveTotalDebtBase > initialData.aaveTotalDebtBase, "Debt should increase");
        assertTrue(finalData.aaveHealthFactor < type(uint256).max, "Health factor should decrease");
        assertTrue(finalData.aaveHealthFactor > 1e18, "Health factor should be above 1.0");

        // Verify collateral asset data
        assertEq(finalData.assets[0].aaveSupplyAmount, collateralAmount, "Collateral supply amount incorrect");
        assertEq(finalData.assets[0].aaveBorrowAmount, 0, "Should not have borrowed collateral asset");
        assertEq(finalData.assets[0].tokenBalance, 0, "Token balance should be 0 after lending");
        assertEq(finalData.assets[0].aTokenBalance, collateralAmount, "aToken balance incorrect");

        // Verify borrowed asset data
        assertEq(finalData.assets[1].aaveSupplyAmount, 0, "Should not have supplied borrow asset");
        assertApproxEqAbs(finalData.assets[1].aaveBorrowAmount, borrowAmount, 1, "Borrow amount incorrect");
        assertEq(finalData.assets[1].tokenBalance, borrowAmount, "Should have borrowed tokens");
        assertEq(finalData.assets[1].aTokenBalance, 0, "Should not have aTokens for borrowed asset");
    }

    function testGetAccountData_ComplexPosition() public {
        // Test with multiple supplies and borrows
        address[] memory assets = new address[](3);
        assets[0] = USDC_ARBITRUM; // Primary collateral
        assets[1] = USDT_ARBITRUM; // Will supply and borrow
        assets[2] = WETH_ARBITRUM; // Will borrow

        uint256 usdcSupply = 10000e6; // 10,000 USDC
        uint256 usdtSupply = 5000e6; // 5,000 USDT
        uint256 usdtBorrow = 2000e6; // 2,000 USDT
        uint256 wethBorrow = 1e18; // 1 WETH

        // Supply USDC
        deal(USDC_ARBITRUM, address(accessPoint), usdcSupply);
        vm.prank(alice0);
        accessPoint.execute(
            address(aaveLendWorkflow), abi.encodeWithSelector(AaveLendWorkflow.lend.selector, USDC_ARBITRUM, usdcSupply)
        );

        // Supply USDT
        deal(USDT_ARBITRUM, address(accessPoint), usdtSupply);
        vm.prank(alice0);
        accessPoint.execute(
            address(aaveLendWorkflow), abi.encodeWithSelector(AaveLendWorkflow.lend.selector, USDT_ARBITRUM, usdtSupply)
        );

        // Borrow USDT
        vm.prank(alice0);
        accessPoint.execute(
            address(aaveBorrowWorkflow),
            abi.encodeWithSelector(AaveBorrowWorkflow.borrow.selector, USDT_ARBITRUM, usdtBorrow)
        );

        // Borrow WETH
        vm.prank(alice0);
        accessPoint.execute(
            address(aaveBorrowWorkflow),
            abi.encodeWithSelector(AaveBorrowWorkflow.borrow.selector, WETH_ARBITRUM, wethBorrow)
        );

        // Get final position data
        Viewer.AccountData memory data = viewer.getAccountData(assets, alice0);

        // Verify account metrics
        assertTrue(data.aaveTotalCollateralBase > 0, "Should have collateral");
        assertTrue(data.aaveTotalDebtBase > 0, "Should have debt");
        assertTrue(data.aaveHealthFactor > 1e18, "Health factor should be above 1.0");
        assertTrue(data.aaveHealthFactor < type(uint256).max, "Health factor should not be max");

        // Verify USDC position (only supply)
        assertEq(data.assets[0].aaveSupplyAmount, usdcSupply, "USDC supply incorrect");
        assertEq(data.assets[0].aaveBorrowAmount, 0, "Should not have USDC borrow");
        assertEq(data.assets[0].tokenBalance, 0, "Should not have USDC balance");
        assertEq(data.assets[0].aTokenBalance, usdcSupply, "USDC aToken balance incorrect");

        // Verify USDT position (both supply and borrow)
        assertEq(data.assets[1].aaveSupplyAmount, usdtSupply, "USDT supply incorrect");
        assertEq(data.assets[1].aaveBorrowAmount, usdtBorrow, "USDT borrow incorrect");
        assertEq(data.assets[1].tokenBalance, usdtBorrow, "USDT balance incorrect");
        assertEq(data.assets[1].aTokenBalance, usdtSupply, "USDT aToken balance incorrect");

        // Verify WETH position (only borrow)
        assertEq(data.assets[2].aaveSupplyAmount, 0, "Should not have WETH supply");
        assertEq(data.assets[2].aaveBorrowAmount, wethBorrow, "WETH borrow incorrect");
        assertEq(data.assets[2].tokenBalance, wethBorrow, "WETH balance incorrect");
        assertEq(data.assets[2].aTokenBalance, 0, "Should not have WETH aToken balance");
    }
}
