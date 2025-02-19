#!/usr/bin/env bash

# Usage: sum-amounts-range.sh <filename> <min_price> <max_price>
#
# Example:
#   ./sum-amounts-range.sh data.txt 20000000 30000000
#
# This script reads lines from the given file, which must have the format:
#   address  amount  price  priority
#
# It sums the 'amount' values of lines where 'price' is between <min_price> and <max_price> (inclusive).

if [ $# -ne 3 ]; then
  echo "Usage: $0 <filename> <min_price> <max_price>"
  exit 1
fi

FILENAME="$1"
MIN_PRICE="$2"
MAX_PRICE="$3"

awk -v minp="$MIN_PRICE" -v maxp="$MAX_PRICE" '
  $3 >= minp && $3 <= maxp {
    sum += $2
  }
  END {
    print sum
  }
' "$FILENAME"
