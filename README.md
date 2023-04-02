# Kinto ID

## Deploy a new proxy and 1st version

Copy .env.sample to .env and fill the values.

```
source.env && forge script script/deploy.sol:KintoInitialDeployScript --rpc-url $KINTO_RPC_URL --broadcast -vvvv
```

## Upgrade to a new version

TODO

## Test

Check that the contract is deployed:

cast call <PROXY_ADD> "name()(string)" --rpc-url $KINTO_RPC_URL

Call KYC on an address

```
cast call <PROXY_ADD> "isKYC(address)(bool)" 0xa8beb41cf4721121ea58837ebdbd36169a7f246e  --rpc-url $KINTO_RPC_URL
```
