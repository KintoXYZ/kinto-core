// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./IKintoID.sol";
import "./IKintoWalletFactory.sol";
import "./IFaucet.sol";
import "./IEngenCredits.sol";

interface IEngenCredits {
    /* ============ Errors ============ */
    error TransfersAlreadyEnabled();
    error BurnsAlreadyEnabled();
    error LengthMismatch();
    error MintNotAllowed();
    error NoTokensToMint();
    error TransfersNotEnabled();

    /* ============ Functions ============ */

    function mint(address to, uint256 amount) external;

    function mintCredits() external;

    function setTransfersEnabled(bool _transfersEnabled) external;

    function setBurnsEnabled(bool _burnsEnabled) external;

    function setCredits(address[] calldata _addresses, uint256[] calldata _credits) external;

    /* ============ Basic Viewers ============ */

    function getPastVotes(address account, uint256 timepoint) external view returns (uint256);

    function getPastTotalSupply(uint256 timepoint) external view returns (uint256);

    function clock() external view returns (uint48);

    function CLOCK_MODE() external pure returns (string memory);

    /* ============ Constants and attrs ============ */

    function earnedCredits(address account) external view returns (uint256);

    function totalCredits() external view returns (uint256);

    function transfersEnabled() external view returns (bool);

    function burnsEnabled() external view returns (bool);
}
