#!/bin/bash

set -eou pipefail
set -x

/usr/sbin/useradd --create-home regular_user
/usr/sbin/useradd --create-home some_test_user1
/usr/sbin/useradd --create-home some_test_user2
