FROM ubuntu:22.04
LABEL VERSION="20230912"

RUN apt-get update
RUN apt-get -y upgrade
RUN apt-get install -y gcc git
RUN apt-get install -y build-essential
RUN apt-get install -y sudo pkg-config fuse3 libfuse3-3 libfuse3-dev libsqlite3-dev libssl-dev sqlite3 valgrind libicu-dev libicu70 
RUN apt-get install -y locales locales-all libsodium-dev

RUN echo "" >> /etc/fuse.conf
RUN echo "user_allow_other" >> /etc/fuse.conf

RUN echo "" >> /etc/environment
RUN echo "LC_ALL=en_US.UTF-8" >> /etc/environment

RUN echo "#!/bin/bash" > /build.sh
RUN echo "cd /source && ./helper_01_vlang_install.sh" >> /build.sh
RUN echo "cd /source && ./helper_02_create_test_users.sh" >> /build.sh
RUN echo "cd /source && ./make-testhelpers-suid.sh" >> /build.sh
RUN chmod a+x /build.sh

RUN echo "#!/bin/bash" > /run.sh
RUN echo "LOGNAME=regular_user" >> /run.sh
RUN echo "export LOGNAME" >> /run.sh
RUN echo "LC_ALL=en_US.UTF-8" >> /run.sh
RUN echo "export LC_ALL" >> /run.sh
RUN echo "v install libsodium" >> /run.sh
RUN echo "mkdir /tmp/test_only_default_vpassman_mountpoint" >> /run.sh
#RUN echo "cd /source/src-service && ./test-one-in-auto-mountpoint.sh fuse_fundamentals_test.v" >> /run.sh
RUN echo "cd /source/src-service && ./test-all-quiet.sh" >> /run.sh
#RUN echo "cd /source/src-service && ./test-all-using-auto-mountdir.sh" >> /run.sh
RUN chmod a+x /run.sh

RUN echo "#!/bin/bash" > /entry.sh
RUN echo "/build.sh || exit 1" >> /entry.sh
RUN echo "su --command /run.sh regular_user" >> /entry.sh
RUN chmod a+x /entry.sh

ENV LC_ALL=en_US.UTF-8

#ENTRYPOINT "/bin/bash"
ENTRYPOINT "/entry.sh"
