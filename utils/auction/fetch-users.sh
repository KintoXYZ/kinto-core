#!/bin/bash
set -euo pipefail

# Ensure KINTO_RPC_URL is set
if [ -z "${KINTO_RPC_URL:-}" ]; then
  echo "Error: KINTO_RPC_URL is not set."
  exit 1
fi

# Fetch logs and process them:
# 1. `cast logs` fetches the logs for the Deposited event.
# 2. `awk` selects the appropriate lines (skip two lines after matching "topics: [").
# 3. `xargs` runs `cast parse-bytes32-address` for each address.
# 4. `sort -u` ensures only unique addresses are written to the file.
cast logs --rpc-url "$KINTO_RPC_URL" --from-block 731179 --to-block latest \
  'Deposited(address indexed user, uint256 amount)' \
  --address 0x5a1E00884e35bF2dC39Af51712D08bEF24b1817f | \
awk '/topics: \[/{getline; getline; print}' | \
xargs -n1 cast parse-bytes32-address | sort -u > ./script/data/auction/users.txt 

echo "Unique user addresses saved to 'users'"
