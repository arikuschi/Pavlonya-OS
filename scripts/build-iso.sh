#!/usr/bin/bash
# Installations-ISO bauen. Standard: das lokal gebaute Image.
#   scripts/build-iso.sh                                  # localhost/pavlonya-os:44
#   scripts/build-iso.sh ghcr.io/<name>/pavlonya-os:44    # Image von GitHub
set -euxo pipefail
cd "$(dirname "$0")/.."
IMAGE="${1:-localhost/pavlonya-os:44}"
mkdir -p output
[[ "${IMAGE}" == localhost/* ]] || sudo podman pull "${IMAGE}"
sudo podman run --rm -it --privileged --pull=newer \
    --security-opt label=type:unconfined_t \
    -v ./output:/output \
    -v /var/lib/containers/storage:/var/lib/containers/storage \
    -v ./disk_config/iso.toml:/config.toml:ro \
    quay.io/centos-bootc/bootc-image-builder:latest \
    --type anaconda-iso --rootfs xfs --chown "$(id -u):$(id -g)" \
    "${IMAGE}"
find output -name '*.iso' -exec ls -lh {} +
