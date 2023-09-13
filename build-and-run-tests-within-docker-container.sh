#!/bin/bash

set -eou pipefail
set -x

mkdir -p temp/empty
mkdir -p temp/vlang

CURDIR=$(pwd)

# to prepare C and V capable environment
docker image build \
	--rm -f build-and-run-tests-within-docker-container.Dockerfile -t="build-and-run-tests-within-docker-container" \
	 "${CURDIR}/temp/empty"

docker container rm --force "build-and-run-tests-within-docker-container" || echo "ok, no old container present"

CONTAINER_ID=$(docker container create -t -i --privileged \
	--device /dev/fuse \
	--security-opt seccomp=unconfined \
	-v "${CURDIR}:/source" \
	--rm --name "build-and-run-tests-within-docker-container" \
	"build-and-run-tests-within-docker-container")

docker container start --attach --interactive ${CONTAINER_ID}
echo "OK"

#	--cap-drop all \
#	--cap-add cap_sys_admin \
#	--cap-add cap_setuid \
#	--cap-add cap_sys_ptrace \