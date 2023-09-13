#!/bin/bash

set -eou pipefail
set -x

mkdir -p temp/empty
mkdir -p temp/vlang

CURDIR=$(pwd)

# to prepare C and V capable environment
podman image build \
	-v "${CURDIR}:/source" \
	--rm -f build-and-run-tests-within-podman-container.Dockerfile -t="build-and-run-tests-within-podman-container" \
	 "${CURDIR}/temp/empty"

podman container rm --force "build-and-run-tests-within-podman-container" || echo "ok, no old container present"

podman container create -t -i \
	--cap-drop all \
	--cap-add cap_sys_admin \
	--cap-add cap_setuid \
	--cap-add cap_sys_ptrace \
	--device /dev/fuse \
	--security-opt seccomp=unconfined \
	-v "${CURDIR}:/source" \
	--rm --name "build-and-run-tests-within-podman-container" \
	"build-and-run-tests-within-podman-container"

podman container start --attach --interactive "build-and-run-tests-within-podman-container"
echo "OK"
