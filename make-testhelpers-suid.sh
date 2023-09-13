#!/bin/bash

set -eou pipefail
set -x

cd src-testhelper-insecure-fullpath-of-pid
v main.c.v -o testhelper-insecure-fullpath-of-pid.bin
sudo chown root testhelper-insecure-fullpath-of-pid.bin
sudo chmod +s testhelper-insecure-fullpath-of-pid.bin
cd ..

cd src-testhelper-my-suid-cat
v main.v -o testhelper-my-suid-cat.bin
sudo chown root testhelper-my-suid-cat.bin
sudo chmod +s testhelper-my-suid-cat.bin
cd ..
