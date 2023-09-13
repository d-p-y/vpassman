#!/bin/bash

set -eou pipefail

BASE_DIR=$(cd $(dirname "${BASH_SOURCE[0]}") && pwd)
THIS_SCRIPT="${BASE_DIR}/$(basename $0)"

if [[ ! -v "RECURSION" ]]; then
	export RECURSION="1"
	exec ../set-variables-and-execute-args.sh "${THIS_SCRIPT}" $1
fi

export VPASSMAN_MOUNTPOINT="$VPASSMAN_TEST_MOUNTPOINT_LOCATION_REGULAR"

export CFLAGS="-Wall -Wshadow -fstack-protector-all -mshstk -fcf-protection=full -fsanitize=address -fno-omit-frame-pointer"
export LDFLAGS="-fsanitize=address -fno-omit-frame-pointer"

rm -rf /tmp/v
rm -rf ~/.vmodules/cache/*

v -v -g -cg -keepc -cc gcc -gc none -stats test $1
