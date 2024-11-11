// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {IERC20} from "@openzeppelin-5.0.1/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin-5.0.1/contracts/token/ERC20/utils/SafeERC20.sol";
import {Address} from "@openzeppelin-5.0.1/contracts/utils/Address.sol";
import {IERC4626} from "@openzeppelin-5.0.1/contracts/interfaces/IERC4626.sol";

import {IAavePool, IPoolAddressesProvider, IStaticATokenFactory} from "@kinto-core/interfaces/external/IAavePool.sol";
import {IBridge} from "@kinto-core/interfaces/bridger/IBridge.sol";
import {IAccessPoint} from "@kinto-core/interfaces/IAccessPoint.sol";
import {IBridger} from "@kinto-core/interfaces/bridger/IBridger.sol";

contract LendAndBridgeWorkflow {
    using SafeERC20 for IERC20;
    /// @notice The address of the Bridger contract

    IBridger public immutable bridger;
    IPoolAddressesProvider public immutable poolAddressProvider;
    IStaticATokenFactory public immutable staticATokenFactory;

    constructor(IBridger bridger_, address poolAddressProvider_, address staticATokenFactory_) {
        bridger = bridger_;
        poolAddressProvider = IPoolAddressesProvider(poolAddressProvider_);
        staticATokenFactory = IStaticATokenFactory(staticATokenFactory_);
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

        address aStaticToken = staticATokenFactory.getStaticAToken(inputAsset);

        // Approve max allowance to save on gas for future transfers
        if (IERC20(inputAsset).allowance(address(this), address(aStaticToken)) < amount) {
            IERC20(inputAsset).forceApprove(address(aStaticToken), type(uint256).max);
        }

        uint256 aTokenAmount = IERC4626(aStaticToken).deposit(amount, address(this));

        // Approve max allowance to save on gas for future transfers
        if (IERC20(aStaticToken).allowance(address(this), address(bridger)) < amount) {
            IERC20(aStaticToken).forceApprove(address(bridger), type(uint256).max);
        }

        return bridger.depositERC20(
            aStaticToken, aTokenAmount, kintoWallet, aStaticToken, aTokenAmount, bytes(""), bridgeData
        );
    }
}
