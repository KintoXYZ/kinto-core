# Bridger Contract Documentation

## Overview

The `Bridger` contract allows users to bridge tokens into the Kinto Layer 2 (L2) network. The contract supports various functionalities, including token swaps, deposits via signatures, and handling both ERC20 tokens and ETH. The contract is designed to be upgradeable and includes security features such as pausing and reentrancy protection.

## Table of Contents

1. [Events](#events)
2. [Constants & Immutables](#constants--immutables)
3. [State Variables](#state-variables)
4. [Modifiers](#modifiers)
5. [Constructor & Upgrades](#constructor--upgrades)
6. [Pause and Unpause](#pause-and-unpause)
7. [Public Functions](#public-functions)
8. [Private Functions](#private-functions)
9. [Signature Recovery](#signature-recovery)
10. [EIP-712 Helpers](#eip-712-helpers)
11. [Fallback](#fallback)

## Events

### `Deposit`

Emitted when a deposit is made.

- `from`: The address of the depositor.
- `wallet`: The address of the Kinto wallet on L2.
- `asset`: The address of the input asset.
- `amount`: The amount of the input asset.
- `assetBought`: The address of the final asset.
- `amountBought`: The amount of the final asset bought.

## Constants & Immutables

- `ETH`: The address representing ETH.
- `WETH`: The WETH contract instance.
- `DAI`: The address of the DAI token.
- `USDe`: The address of the USDe token.
- `sUSDe`: The address of the sUSDe token.
- `wstETH`: The address of the wstETH token.
- `domainSeparator`: The domain separator for EIP-712.
- `l2Vault`: The address of the L2 vault.
- `swapRouter`: The address of the 0x exchange proxy through which swaps are executed.

## State Variables

- `senderAccount`: The address of the sender account.
- `nonces`: Nonces for replay protection.
- `depositCount`: Count of deposits.

## Modifiers

### `onlyPrivileged`

Restricts access to only the owner or sender account.

### `onlySignerVerified`

Checks that the signature is valid and has not been used yet.

## Constructor & Upgrades

### `constructor`

Initializes the contract by setting the exchange proxy address.

### `initialize`

Initializes the contract by setting the sender account.

### `_authorizeUpgrade`

Authorizes the upgrade. Only callable by the owner.

## Pause and Unpause

### `pause`

Pauses the contract. Only callable by the owner.

### `unpause`

Unpauses the contract. Only callable by the owner.

### `setSenderAccount`

Sets the sender account. Only callable by the owner.

## Public Functions

### `depositBySig`

Deposits tokens by signature.

### `depositERC20`

Deposits the specified amount of ERC20 tokens into the Kinto L2.

### `depositETH`

Deposits the specified amount of ETH into the Kinto L2 as the final asset.

## Private Functions

### `_deposit`

Handles deposits.

### `_swap`

Handles token swaps.

### `_stakeEthToWstEth`

Stakes ETH to wstETH.

### `_permit`

Permits the spender to spend the specified amount of tokens on behalf of the owner.

### `_fillQuote`

Swaps ERC20 tokens using a 0x-API quote.

## Signature Recovery

### `onlySignerVerified`

Checks that the signature is valid and has not been used yet.

## EIP-712 Helpers

### `_domainSeparatorV4`

Returns the domain separator for the current chain.

### `_hashSignatureData`

Hashes the signature data.

## Fallback

### `receive`

Fallback function to receive ETH.
