# Kinto ID

## Requirements

Copy .env.sample to .env and fill the values.

After you deploy the proxy make sure to fill its address as well.

## Deploy a new proxy and 1st version

```
source .env && forge script script/deploy.sol:KintoInitialDeployScript --rpc-url $KINTO_RPC_URL --broadcast -vvvv
```

## Upgrade to a new version

```
source .env && forge script script/deploy.sol:KintoUpgradeScript --rpc-url $KINTO_RPC_URL --broadcast -vvvv
```

## Test

Check that the contract is deployed:

cast call $ID_PROXY_ADDRESS "name()(string)" --rpc-url $KINTO_RPC_URL

Call KYC on an address

```
cast call $ID_PROXY_ADDRESS "isKYC(address)(bool)" 0xa8beb41cf4721121ea58837ebdbd36169a7f246e  --rpc-url $KINTO_RPC_URL
```
