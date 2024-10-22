#!/bin/bash

# Repeat the command 100 times
for i in {1..100}; do
    echo "Execution $i"
    cast send --private-key $PRIVATE_KEY $KINTOID  "name()" --legacy --rpc-url $KINTO_RPC_URL
done
