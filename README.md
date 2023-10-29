![Slide 1](https://github.com/KintoXYZ/kinto-id/assets/541599/c9345010-21c6-411c-bbf8-31a6727d8c48)

# Kinto ID
Kinto ID gives developers all the functionality to verify on-chain whether a given address has the appropriate KYC, accreditation requirements. Kinto ID also provides functionality to check AML sanctions.

## Docs

Check to our gitbook to see all the documentation.

[Docs](https://docs.kinto.xyz/developers)

## Relevant Public Methods

You can check all the public methods in the interface [here](https://github.com/KintoXYZ/kinto-id/blob/main/src/interfaces/IKintoID.sol)

```
    function isKYC(address _account) external view returns (bool);

    function isSanctionsMonitored(uint32 _days) external view returns (bool);

    function isSanctionsSafe(address _account) external view returns (bool);

    function isSanctionsSafeIn(address _account, uint8 _countryId) external view returns (bool);

    function isCompany(address _account) external view returns (bool);

    function isIndividual(address _account) external view returns (bool);

    function mintedAt(address _account) external view returns (uint256);

    function hasTrait(address _account, uint8 index) external view returns (bool);

    function traits(address _account) external view returns (bool[] memory);
```

## Requirements

- Install [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Copy .env.sample to .env and fill the values. After you deploy the proxy make sure to fill its address as well.

### Enable CREATE2 in a custom chain

Fund the signer `0x3fab184622dc19b6109349b94811493bf2a45362` to deploy the arachnid proxy:

```
cast send 0x3fab184622dc19b6109349b94811493bf2a45362 --value 0.03ether --private-key <your_private_key> --rpc-url $KINTO_RPC_URL
```

Send the following transaction using foundry. Make sure you disable EIP-155:

```
cast publish f8a58085174876e800830186a08080b853604580600e600039806000f350fe7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe03601600081602082378035828234f58015156039578182fd5b8082525050506014600cf31ba02222222222222222222222222222222222222222222222222222222222222222a02222222222222222222222222222222222222222222222222222222222222222  --rpc-url <NODE_OPEN_EIP155>
```
Now we should have the proxy live at `0x4e59b44847b379578588920ca78fbf26c0b4956c`.

## Deploying

### Deploy all core contracts

Here is the code to deploy the Kinto ID and all the contracts required by account abstraction under the PUBLIC_KEY/PRIVATE_KEY signer:

```
source .env && forge script script/deploy.sol:KintoInitialDeployScript --rpc-url $KINTO_RPC_URL --broadcast -vvvv --skip-simulation --slow
```

### Create Kinto Smart Account

After you have deployed all core contracts, you can call the following script to deploy an account.
If it already exists, it won't deploy it.

```
source .env && forge script script/test.sol:KintoDeployTestWalletScript --rpc-url $KINTO_RPC_URL --broadcast -vvvv  --skip-simulation --slow
```

### Test Kinto Smart Account with Counter contract

After you have deployed all core contracts and you have a wallet, you can call the following script to deploy an custom contract and execute an op through your smart account.
If it already exists, it won't deploy it.

```
source .env && forge script script/test.sol:KintoDeployTestCounter --rpc-url $KINTO_RPC_URL --broadcast -vvvv  --skip-simulation --slow
```

### Upgrade Kinto ID to a new version

```
source .env && forge script script/upgrade.sol:KintoIDUpgradeScript --rpc-url $KINTO_RPC_URL --broadcast -vvvv
```

### Deploying manually other contracts

In order to deploy non upgradeable contracts, use the following command:

```
forge create --rpc-url $KINTO_RPC_URL --private-key <your_private_key> src/<CONTRACT_NAME>
```

### Verifying smart contracts on blockscout

On Testnet:

```
forge verify-contract --watch --verifier blockscout --chain-id 42888 --verifier-url http://test-explorer.kinto.xyz/api --num-of-optimizations 100000 0xE40C427226D78060062670E341b0d8D8e66d725A ETHPriceIsRight
```

## Testing

In order to run the tests, execute the following command:

```
forge test
```

### Calling the Kinto ID smart contract

Check that the contract is deployed:

cast call $ID_PROXY_ADDRESS "name()(string)" --rpc-url $KINTO_RPC_URL

Call KYC on an address

```
cast call $ID_PROXY_ADDRESS "isKYC(address)(bool)" 0xa8beb41cf4721121ea58837ebdbd36169a7f246e  --rpc-url $KINTO_RPC_URL
```

### Funding a smart contract that pays for the transactions of its users

```
cast send <ENTRYPOINT_ADDRESS> "addDepositFor(address)" <ADDR> --value 0.1ether
```

### Exporting contracts ABI for frontend

```
yarn run export-testnet
```