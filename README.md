# VPASSMAN

Experimental, incomplete, Password Manager written in [V language](https://github.com/vlang/v).

## Story
In 2022 I've became intrigued with new*ish* memory safe and lowlevel language. 
I've decided to learn/evaluate it to see if it is capable enough and stable enough for nontrivial apps.
Non trivial app that I attempted to implement was this project. Its main idea was to have encrypted [SQLite database](https://www.sqlite.org) containing secrets exposed as virtual files. 
Unencrypted SQLite would work purely in memory filesystem to prevent leakage. SQLite would "think" it is file backed thus I would be able to restore unencrypted db file from encrypted file (or back up to encrypted file) easily and securely. 
Database schema would contain rules and policies so that apps asking for secrets would either 
* get access 
* or be denied 
* or would be blocked until user decides to grant or deny using GUI/TUI

Idea of secrets kept in memory somewhere and later exposed as virtual files originates from [docker secrets](https://docs.docker.com/engine/swarm/secrets/).

## Example use case

Linux user `bob`, executes `cat /opt/secrets/by-name/dropbox/access_token` in some script to get some file from Dropbox. 
`/opt/secrets/` is a virtual filesystem provided by VPASSMAN via [FUSE](https://en.wikipedia.org/wiki/Filesystem_in_Userspace). 
VPASSMAN verifies whether `/usr/bin/cat` executed by user `bob` is allowed by policies present in database. 
VPASSMAN sees that there's explicit `permit` policy letting `/usr/bin/cat` executed by `bob` to access it hence `bob` sees that his command executed almost immediately.  

## Internals 

* wraps [FUSE](https://github.com/libfuse/libfuse) to expose secrets as virtual files and be able to do grant/deny reading/writing on the fly by VPASSMAN
* uses [SQLite VFS](https://www.sqlite.org/vfs.html) to be able to have SQLite database as file. It is because purely in memory sqlite database backups/restores are [hard](https://www.sqlite.org/backup.html).
* utilizes [memfd_create](https://man7.org/linux/man-pages/man2/memfd_create.2.html) to force SQLite to think that it writes to disk but in reality it works in memory
* uses [libsodium](https://github.com/jedisct1/libsodium) via its [vlang wrappers](https://github.com/vlang/libsodium) that I helped to write

## Tests

There are few dozens of tests covering almost all aspects of the program(e.g. verify if FUSE callbacks are called, if SQLite VFS is working, if policies are working). 
As tests need to use multiple users and to build and create suid programs its most convenient to execute it within unprivileged linux container. 
Easiest to run them is to execute `build-and-run-tests-within-podman-container.sh` that internally utilizes [podman containers](https://podman.io/) with few capabilities to let it mount fuse filesystems inside and for suid programs inside to read `/proc` filesystem to have pid-to-actual-fullpath feature. 

You can also use `build-and-run-tests-within-docker-container.sh` that utilizes `docker` instead of `podman`. It is more convoluted (volumes are not supported in building phase).

Both scripts are parts of followin github actions workflow:
![status](https://github.com/d-p-y/vpassman/actions/workflows/ubuntu.yml/badge.svg)

## Current state as of 2023-09

It mostly works in a work-in-progress simple multithreaded terminal UI mode but there seem to be memory problems with garbage collection (hence `-gc none` in test parameters).
It requires `gcc` compiler as program uses [nested functions](https://gcc.gnu.org/onlinedocs/gcc/Nested-Functions.html) to easily provide FUSE wrappers into V code.  
V is nice, its ORM is cool *but* not mature enough yet hence manual SQL after ORM is needed.   
There are issues preventing complete SQLite VFS usage [e.g. xFileSize is blocked by](https://github.com/vlang/v/issues/16291).  
I plan to watch it grow and see it stabilize. Next steps would eventually use [V UI](https://github.com/vlang/ui) (as it was re-licensed recently) and add communication over unix socket [as it is possible to know requesting process](https://stackoverflow.com/questions/8104904/identify-program-that-connects-to-a-unix-domain-socket).

# Notes 

Highly recommend to use [Jetbrains CLion IDE](https://www.jetbrains.com/clion/) with [Vlang plugin](https://plugins.jetbrains.com/plugin/20287-vlang/docs/quick-start-guide.html).
