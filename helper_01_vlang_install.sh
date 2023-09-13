#!/bin/bash

set -eou pipefail
set -x

cd temp/vlang
if [ ! -d "vlib" ]; 
then
	git clone "https://github.com/vlang/v.git" .
else
	echo "v sources are checked out"
fi

if [ ! -x "v" ]; 
then
	make
else
	echo "v binary is present"
fi

./v symlink
v --version

# to force package tools compilation
v list
v test --help || echo "nevermind"

