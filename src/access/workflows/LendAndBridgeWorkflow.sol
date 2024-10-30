// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {IERC20} from "@openzeppelin-5.0.1/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin-5.0.1/contracts/token/ERC20/utils/SafeERC20.sol";
import {Address} from "@openzeppelin-5.0.1/contracts/utils/Address.sol";

import {IAavePool, ILendingPoolAddressesProvider} from "@kinto-core/interfaces/external/IAavePool.sol";
import {IBridge} from "@kinto-core/interfaces/bridger/IBridge.sol";
import {IAccessPoint} from "@kinto-core/interfaces/IAccessPoint.sol";
import {IBridger} from "@kinto-core/interfaces/bridger/IBridger.sol";

contract LendAndBridgeWorkflow {
    using SafeERC20 for IERC20;
    /// @notice The address of the Bridger contract

    IBridger public immutable bridger;
    ILendingPoolAddressesProvider public immutable poolAddressProvider;

    constructor(IBridger bridger_, address poolAddressProvider_) {
        bridger = bridger_;
        poolAddressProvider = ILendingPoolAddressesProvider(poolAddressProvider_);
    }

    function lendAndBridge(
        address inputAsset,
        uint256 amount,
        address kintoWallet,
        IBridger.BridgeData calldata bridgeData
    ) external payable returns (uint256 amountOut) {
        if (amount == 0) {
            amount = IERC20(inputAsset).balanceOf(address(this));
        }

        address pool = poolAddressProvider.getLendingPool();
        // Get aToken address from reserve data
        IAavePool.ReserveDataLegacy memory reserveData = IAavePool(pool).getReserveData(inputAsset);
        address aToken = reserveData.aTokenAddress;

        // Approve max allowance to save on gas for future transfers
        if (IERC20(inputAsset).allowance(address(this), address(pool)) < amount) {
            IERC20(inputAsset).forceApprove(address(pool), type(uint256).max);
        }

        IAavePool(pool).supply(inputAsset, amount, address(this), 0);
        uint256 aTokenAmount = IERC20(aToken).balanceOf(address(this));

        return bridger.depositERC20(aToken, aTokenAmount, kintoWallet, aToken, aTokenAmount, bytes(""), bridgeData);
    }
}
