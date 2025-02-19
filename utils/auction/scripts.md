./utils/auction/fetch-users.sh

./utils/auction/fetch-bids.sh

node utils/auction/clear-auction.js

node utils/auction/build-merkle-proof.mjs

ROOT=0x7dfe5c2d9e5871561b754e68eefb9015be76484d7b935fa34f6cba51f6b2c9b9 forge script script/actions/set-auction-root.s.sol --rpc-url kinto -vvvv  --gas-estimate-multiplier 3000 --skip-simulation
