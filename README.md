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

## Testing

In order to run the tests, execute the following command:

```
forge test
```

## Deploy a new proxy and 1st version

```
source .env && forge script script/deploy.sol:KintoInitialDeployScript --rpc-url $KINTO_RPC_URL --broadcast -vvvv
```

## Upgrade to a new version

```
source .env && forge script script/deploy.sol:KintoUpgradeScript --rpc-url $KINTO_RPC_URL --broadcast -vvvv
```

## Calling the smart contract

Check that the contract is deployed:

cast call $ID_PROXY_ADDRESS "name()(string)" --rpc-url $KINTO_RPC_URL

Call KYC on an address

```
cast call $ID_PROXY_ADDRESS "isKYC(address)(bool)" 0xa8beb41cf4721121ea58837ebdbd36169a7f246e  --rpc-url $KINTO_RPC_URL
```

## Deploying other contracts

In order to deploy non upgradeable contracts, use the following command:

```
forge create --rpc-url $KINTO_RPC_URL --private-key <your_private_key> src/<CONTRACT_NAME>
```

## Verifying smart contracts on blockscout

On Testnet:

```
forge verify-contract --watch --verifier blockscout --chain-id 42888 --verifier-url http://test-explorer.kinto.xyz/api --num-of-optimizations 100000 0xE40C427226D78060062670E341b0d8D8e66d725A ETHPriceIsRight
```
