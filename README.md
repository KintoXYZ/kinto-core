![Slide 1](https://github.com/KintoXYZ/kinto-id/assets/541599/c9345010-21c6-411c-bbf8-31a6727d8c48)

[![codecov](https://codecov.io/gh/KintoXYZ/kinto-core/graph/badge.svg?token=JXQ1EQTRV1)](https://codecov.io/gh/KintoXYZ/kinto-core)

# What is Kinto?
Kinto is an **Ethereum L2 rollup designed to accelerate the transition to an on-chain financial system**. It features **permissionless KYC/AML and native account abstraction** to solve the two biggest blockers to mainstream adoption: compliance and user experience.

## Docs

Check our gitbook to see all the documentation.

[Docs](https://docs.kinto.xyz/developers)

# High Level Architecture

## Modular Stack
We adopted the modular thesis to maximize decentralization, credible neutrality, and scalability. The modular thesis, where different layers of the blockchain architecture are separated and optimized, allows each layer to function more efficiently. Let's analyze the different components of the Kinto rollup:

- **Settlement**: From day one, Kinto used Ethereum as the settlement layer. Ethereum is the network with the most mature infrastructure for on-chain financial applications and the most censorship-resistant, neutral block space.
- **Execution**: On the execution layer, we announced our partnership with Arbitrum a few weeks ago, becoming the first Arbitrum-based L2. Arbitrum is the undisputed L2 leader in TVL, maturity, and size of its DeFi ecosystem.
- **Data Availability**:  We have partnered with Celestia.  Kinto will tap into Celestia via Blobstream on Ethereum Mainnet, which provides L2s secure on-chain access to Celestia’s data root for integration with the bridge and Nitro. You can read our announcement here.
- **Sequencer**: Initially, Kinto will run its sequencer, but we are talking with Espresso and others to transition to a decentralized sequencing system.

## Kinto Unique Features

* **KYC & AML at the chain level**. Every user and developer must undergo our user-owned KYC process before transacting on the network.
* **Smart-Contract Wallets Only**. Users must create their non-custodial Kinto Wallet. Transactions initiated by EOAs are disabled and must be sent via Account Abstraction and its Entry Point.
* **Sybil Resistance**. Having KYC at the chain level opens a new design space where every application is automatically sybil-resistant.
* **Higher Level of Security**. Combining KYC/AML and Sybil Resistance with smart contract wallets provides a higher level of safety for both users and developers.

You can read more about our architecture [here](https://docs.kinto.xyz/kinto-the-safe-l2/building-on-kinto/kinto-rollup-architecture).

## Important Technical Considerations

* Kinto is fully EVM-compatible.
* To send a transaction, you must have a KintoWallet, and its first signer must hold a Kinto ID. The transaction must be sent to the entry point.
* Only five contracts can receive direct transactions from EOAs: EntryPoint, SponsorPaymaster, KintoWalletFactory, Kinto ID and KintoAppRegistry.
* KintoWallet is fully non-custodial, but there is a way for users to recover their accounts through a week-long recovery process.
* EOAs can perform calls that don't alter the chain's state without KYC.
* Users do not need to pay for transactions. Developers will charge users and top up the paymaster to cover the applications users send to their contracts.
* If a user gets added to a sanction list, his NFT will automatically be updated with this information.
* Kinto core contracts are upgradeable. Upgradeable powers will eventually be handed out to governance.

# Development

This repository contains all the core smart contracts available at Kinto.

* Kinto ID gives developers all the functionality to verify on-chain whether a given address has the appropriate KYC, accreditation requirements. Kinto ID also provides functionality to check AML sanctions.
* KintoWallet and KintoWalletFactory have all the code required to create wallets and deploy contracts.
* SponsorPaymaster is the Account Abstraction Paymaster of Kinto.

## Requirements

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Yarn or NPM

## Install dependencies
- Run `yarn install` to install all dependencies 
- Copy `.env.sample` to `.env` and fill the values. After you deploy the proxy make sure to fill its address as well.

### Enable CREATE2 in a custom chain (only needed in a custom chain)

Fund the signer `0x3fab184622dc19b6109349b94811493bf2a45362` to deploy the arachnid proxy:

```
cast send 0x3fab184622dc19b6109349b94811493bf2a45362 --value 0.03ether --private-key <your_private_key> --rpc-url $KINTO_RPC_URL
```

Send the following transaction using foundry. Make sure you disable EIP-155:

```
cast publish f8a58085174876e800830186a08080b853604580600e600039806000f350fe7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe03601600081602082378035828234f58015156039578182fd5b8082525050506014600cf31ba02222222222222222222222222222222222222222222222222222222222222222a02222222222222222222222222222222222222222222222222222222222222222  --rpc-url <NODE_OPEN_EIP155>
```
Now we should have the proxy live at `0x4e59b44847b379578588920ca78fbf26c0b4956c`.

## Testing

In order to run the tests, execute the following command:

```
forge test
```
Alternatively, you run `yarn test`

To run tests on a fork from fokr chain you need to set the env vars `FOUNDRY_PROFILE=fork`
```
FOUNDRY_PROFILE=fork forge test -vvv
```
Alternatively, you run `yarn test-fork`

## Static Analysis

In order to run Slither for static analysis, execute the following command:

```
slither --checklist --solc-remaps "$(tr '\n' ' ' < remappings.txt | xargs)" ./src/
```

## Continous Integration

We use Github Actions to run tests (both local and fork tests) and several other checks.

Everytime a PR is created, the `pull_request.yml` workflow runs which runs the following actions:
- Forge format
- Forge tests
  - Gas report comparison
  - Codecov to check for coverage [![codecov](https://codecov.io/gh/KintoXYZ/kinto-core/graph/badge.svg?token=JXQ1EQTRV1)](https://codecov.io/gh/KintoXYZ/kinto-core)
- Slither analysis (for static analysis)

Everytime a PR is **merged** into `main` (or there's a push directly to it), fork tests are run.

## Coverage
To create a complete coverage report we need to run coverage on local + run coverage on fork and then merge both lcov.info files into one. Finally, we remove the unnecessary files from the report (scripts, tests):

```
forge coverage --report lcov && mv lcov.info lcov-local.info && FOUNDRY_PROFILE=fork forge coverage --report lcov && mv lcov.info lcov-mainnet.info && lcov --add lcov-local.info --add lcov-mainnet.info -o lcov.info && rm lcov-local.info && rm lcov-mainnet.info && lcov --remove lcov.info -o lcov.info "test/*" "script/*" && genhtml lcov.info --branch-coverage --output-dir coverage
```

## Scripts

On the `/script` directory, you can find the following subdirectories:
- `/migrations`: all our executed migrations with contracts upgrades.
- `/samples`: sample scripts to, for example, deploy & interact with other contracts, create a Kinto Wallet, upgrade contracts.
- `/utilts`: scripts with some util actions

Find below the instructions to run some of these scripts:

## Debugging crypto txs

The best way is to use cast with the txhash

```
cast run <tx-hash> --rpc-url $KINTO_RPC_URL
```

For help decoding use the [General Decoding ABI](https://calldata.swiss-knife.xyz/decoder)

### Deploy all core contracts

You can use the `DeployerScript` to deploy all the contracts required by account abstraction under the PUBLIC_KEY/PRIVATE_KEY signer:

```
source .env && forge script script/deploy.s.sol:DeployerScript --rpc-url $KINTO_RPC_URL --broadcast -vvvv --skip-simulation --slow
```

To deploy with ledger:

```
source .env && forge script script/deploy.s.sol:DeployerScript --rpc-url $KINTO_RPC_URL --broadcast --slow --ledger --sender <ADDR> --gas-estimate-multiplier 100 --legacy --skip-simulation --block-gas-limit 8000000000000000000 --verifier blockscout --verifier-url https://kinto-mainnet.calderaexplorer.xyz/api
```

### Create Kinto Smart Account

After you have deployed all core contracts, you can call the following script to deploy an account.
If it already exists, it won't deploy it.

```
source .env && forge script script/samples/createWallet.s.sol:KintoCreateWalletScript --rpc-url $KINTO_RPC_URL --broadcast -vvvv  --skip-simulation --slow
```

### Using your Kinto Smart Account to make calls to contracts

After you have deployed all core contracts and you have created a wallet, you can make calls to other contracts by creating a user operation

#### Counter contract

`KintoCounterScript` deploys a `Counter` contract (skips deployment if already exists) and executes a user operation that calls the `increment()` function using your smart account.

```
source .env && forge script script/samples/counter.s.sol:KintoCounterScript --rpc-url $KINTO_RPC_URL --broadcast -vvvv  --skip-simulation --slow
```

#### Price Guesser

`KintoGuesser` deploys an `ETHPriceIsRight` contract (skips deployment if already exists) and executes a user operation that calls the `enterGuess()` function using your smart account.

```
source .env && forge script script/samples/guesser.s.sol:KintoGuesserScript --rpc-url $KINTO_RPC_URL --broadcast -vvvv  --skip-simulation --slow
```

### Upgrade Kinto ID to a new version

```
source .env && forge script script/samples/upgrades/upgrade.sol:KintoIDUpgradeScript --rpc-url $KINTO_RPC_URL --broadcast -vvvv
```

### Verifying smart contracts on Blockscout

On Testnet:

```
forge verify-contract --watch --verifier blockscout --chain-id 42888 --verifier-url http://test-explorer.kinto.xyz/api --num-of-optimizations 100000 0xE40C427226D78060062670E341b0d8D8e66d725A ETHPriceIsRight
```

On Mainnet:

```
forge verify-contract 0xA6ddF426008E8b7f1a70237bdEfafB5D928bA72E src/wallet/KintoWallet.sol:WalletV7 --verifier-url https://kinto-mainnet.calderaexplorer.xyz/api --constructor-args $(cast abi-encode "constructor(address,address,address)" "0x2843C269D2a64eCfA63548E8B3Fc0FD23B7F70cb" "0xf369f78E3A0492CC4e96a90dae0728A38498e9c7" "0x5A2b641b84b0230C8e75F55d5afd27f4Dbd59d5b")  --verifier blockscout --compiler-version 0.8.23
```
