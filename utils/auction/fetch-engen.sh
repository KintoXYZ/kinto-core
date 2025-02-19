#!/bin/bash

# Ensure KINTO_RPC_URL is set
if [ -z "$KINTO_RPC_URL" ]; then
  echo "Error: KINTO_RPC_URL is not set."
  exit 1
fi

# Output file
output="./script/data/auction/engen-holders-with-balance.txt"
rm -f "$output"   # Remove previous output file if it exists
touch "$output"

# Maximum number of parallel jobs
max_jobs=8

# Function to process a single user
process_user() {
  local user=$1
  local balance

  balance=$(cast call --rpc-url "$KINTO_RPC_URL" \
    0xD1295F0d8789c3E0931A04F91049dB33549E9C8F \
    "balanceOf(address)" "$user" | cast to-dec)

  # Append the result to the output file.
  # Using a newline ensures each record is separate.
  echo "$user $balance" >> "$output"
}

# Read users from file and process in parallel
while IFS= read -r user || [ -n "$user" ]; do
  # Launch the process in the background
  process_user "$user" &

  # Limit the number of parallel jobs
  while [ "$(jobs -r | wc -l)" -ge "$max_jobs" ]; do
    sleep 0.1
  done
done < ./script/data/auction/engen-holders.txt

# Wait for any remaining background processes to finish
wait

echo "Data fetched and stored in $output"
