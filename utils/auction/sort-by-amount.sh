#!/bin/bash

# Check if a filename is provided as an argument
if [ $# -ne 1 ]; then
    echo "Usage: $0 filename"
    exit 1
fi

# Sort the file by the second field (amount) numerically in descending order
sort -k2,2n -r "$1"
