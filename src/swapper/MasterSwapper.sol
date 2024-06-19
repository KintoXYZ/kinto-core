// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/interfaces/IERC721.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";

import "../interfaces/IMasterSwapper.sol";
import "forge-std/console.sol";

/**
 * @title MasterSwapper
 * @dev A viewer class that helps developers to check if an address is KYC'd
 *      Abstracts complexity by checking both wallet and EOA.
 */
contract MasterSwapper is Initializable, UUPSUpgradeable, OwnableUpgradeable, IMasterSwapper {
    /* ============ State Variables ============ */
    mapping(address => bool) public override isRelayer;
    SwapInfo[] public override swaps;
    uint256 lastProcessedSwap;

    /* ============ Constructor & Upgrades ============ */
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Upgrade calling `upgradeTo()`
     */
    function initialize() external initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();
        _transferOwnership(msg.sender);
    }

    /**
     * @dev Authorize the upgrade. Only by an owner.
     * @param newImplementation address of the new implementation
     */
    // This function is called by the proxy contract when the factory is upgraded
    function _authorizeUpgrade(address newImplementation) internal view override {
        (newImplementation);
        if (msg.sender != owner()) revert OnlyOwner();
    }

    /* ============ Modifiers ============ */

    modifier onlyRelayer() {
        if (!isRelayer[msg.sender]) revert OnlyRelayer();
        _;
    }

    /* ============ Swap Methods ============ */

    /**
     * @dev User creates a swap intent
     * @param _sellAsset address of the asset to sell
     * @param _sellAmount amount of the asset to sell
     * @param _buyAsset address of the asset to buy
     * @param _minBuyAmount minimum amount of the asset to buy
     * @param _deadline deadline for the swap
     */
    function createSwapIntent(
        address _sellAsset,
        uint256 _sellAmount,
        address _buyAsset,
        uint256 _minBuyAmount,
        uint256 _deadline
    ) external override {
        require(_sellAsset != address(0) && _buyAsset != address(0) && _buyAsset > 0, "MasterSwapper: invalid params");
        require(IERC20(_sellAsset).balanceOf(address(this)) >= _sellAmount, "MasterSwapper: insufficient balance");
        require(
            IERC20(_sellAsset).allowance(msg.sender, address(this)) >= _sellAmount,
            "MasterSwapper: insufficient allowance"
        );
        require(_deadline > block.timestamp, "MasterSwapper: invalid deadline");
        swaps.push(
            SwapInfo({
                sender: msg.sender,
                sellAsset: _sellAsset,
                sellAmount: _sellAmount,
                buyAsset: _buyAsset,
                minBuyAmount: _minBuyAmount,
                deadline: _deadline
            })
        );
    }

    function processSwapIntents(uint256[] resultingSwapAmounts) external override onlyRelayer {
        require(resultingSwapAmounts.length == swaps.length - lastProcessedSwap, "MasterSwapper: invalid params");
        bool[] memory processed = new bool[](swaps.length - lastProcessedSwap);
        for (uint256 i = lastProcessedSwap; i < swaps.length; i++) {
            SwapInfo memory swap = swaps[i];
            // Deadline expired
            if (swap.deadline < block.timestamp) {
                continue;
            }
            // balance used somewhere else
            if (IERC20(swap.sellAsset).balanceOf(swap.sender) < swap.sellAmount) {
                continue;
            }
            // allowance revoked
            if (IERC20(swap.sellAsset).allowance(swap.sender, address(this)) < swap.sellAmount) {
                continue;
            }
            // too much slippage
            if (resultingSwapAmounts[i] < swap.minBuyAmount) {
                continue;
            }
            // transfer the asset to the contract
            IERC20(swap.sellAsset).transferFrom(swap.sender, address(this), swap.sellAmount);
            processed[i] = true;
        }

        for (uint256 i = lastProcessedSwap; i < swaps.length; i++) {
            if (!processed[i]) {
                continue;
            }
            SwapInfo memory swap = swaps[i];
            // todo: verify with on-chain price oracle as well
            // transfer the asset to the user
            IERC20(swap.buyAsset).transfer(msg.sender, resultingSwapAmounts[i]);
            // todo: keep fee for us
            swap[i].completed = true;
        }

        lastProcessedSwap = swaps.length;
    }

    /* ============ Bridge Methods ============ */

    function bridgeOut(address _asset, uint256 _amount, address _to, uint256 chainId) external override onlyOwner {
        // Function to bridge balances to other chains so we can balance and bridge back to Kinto
    }

    /* ============ Basic Viewers ============ */

    /* ============ Helpers ============ */
}

contract MasterSwapperV2 is MasterSwapper {
    constructor() MasterSwapper() {}
}
