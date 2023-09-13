#!/bin/bash

#v -cg -keepc -gc none main.v && ./main

export CFLAGS="-Wall -Wshadow -fstack-protector-all -mshstk -fcf-protection=full -fsanitize=address -fno-omit-frame-pointer"
export LDFLAGS="-fsanitize=address -fno-omit-frame-pointer"
export VPASSMAN_SERVICE_EXE_PATH="/usr/bin/bash"
export VPASSMAN_SERVICE_PROCESS_USERNAME="dominik"
v -v -cg -keepc -gc none -cc gcc main.c.v && gcc main.c -o main && ./main

