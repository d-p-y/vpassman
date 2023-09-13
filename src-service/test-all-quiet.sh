#!/bin/bash

set -eou pipefail

BASE_DIR=$(cd $(dirname "${BASH_SOURCE[0]}") && pwd)
THIS_SCRIPT="${BASE_DIR}/$(basename $0)"

if [[ ! -v "RECURSION" ]]; then
	export RECURSION="1"
	exec ../set-variables-and-execute-args.sh "${THIS_SCRIPT}"
fi

#export VPASSMAN_MOUNTPOINT="$VPASSMAN_TEST_MOUNTPOINT_LOCATION_REGULAR"

rm -rf /tmp/v
rm -rf ~/.vmodules/cache/*

for f in *_test.v;
do 
    v -cc gcc -gc none -stats test "$f" || exit 1
done;

echo "OK"
