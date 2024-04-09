// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {IERC20} from "@openzeppelin-5.0.1/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin-5.0.1/contracts/token/ERC20/utils/SafeERC20.sol";

import {IAccessPoint} from "../../interfaces/IAccessPoint.sol";

interface IWrappedNativeAsset is IERC20 {
    function deposit() external payable;

    function withdraw(uint256 amount) external;
}

contract WithdrawWorkflow {
    using SafeERC20 for IERC20;

    error NativeWithdrawalFailed();

    function withdrawERC20(IERC20 asset, uint256 amount) external {
        address owner = _getOwner();
        asset.safeTransfer({to: owner, value: amount});
    }

    function withdrawNative(uint256 amount) external {
        address owner = _getOwner();
        (bool sent,) = owner.call{value: amount}("");
        if (!sent) {
            revert NativeWithdrawalFailed();
        }
    }

    function _getOwner() internal view returns (address) {
        return IAccessPoint(address(this)).owner();
    }
}
