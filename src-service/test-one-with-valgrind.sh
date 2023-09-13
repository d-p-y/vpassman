#!/bin/bash

set -eou pipefail

BASE_DIR=$(cd $(dirname "${BASH_SOURCE[0]}") && pwd)
THIS_SCRIPT="${BASE_DIR}/$(basename $0)"

if [[ ! -v "RECURSION" ]]; then
	export RECURSION="1"
	exec ../set-variables-and-execute-args.sh "${THIS_SCRIPT}"
fi

export VPASSMAN_MOUNTPOINT="$VPASSMAN_TEST_MOUNTPOINT_LOCATION_REGULAR"

export CFLAGS="-O0 -Wall -Wshadow -fstack-protector-all -mshstk -fcf-protection=full -fsanitize=address -fno-omit-frame-pointer"
export LDFLAGS="-fsanitize=address -fno-omit-frame-pointer"

rm -rf /tmp/v
rm -rf ~/.vmodules/cache/*


echo valgrind --leak-check=yes v -v -g -cg -keepc -cc gcc -gc none -stats test 
bash

