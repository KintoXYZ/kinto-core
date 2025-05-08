// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >= 0.5.0;

import {Id, IMorpho} from "./IMorpho.sol";
import {IPreLiquidation, PreLiquidationParams} from "./IMorphoPreLiquidation.sol";

interface IPreLiquidationFactory {
    function MORPHO() external view returns (IMorpho);

    function isPreLiquidation(address) external returns (bool);

    function createPreLiquidation(Id id, PreLiquidationParams calldata preLiquidationParams)
        external
        returns (IPreLiquidation preLiquidation);
}
