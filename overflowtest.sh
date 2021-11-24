#!/bin/sh

d_baseDir="$(cd "$(dirname "$0")" && pwd)"
source "${d_baseDir}/includes/helpers.sh"

echo -n "Number of digits before integer overflow: "
checkOverflow
