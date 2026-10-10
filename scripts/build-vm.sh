#!/usr/bin/bash
# qcow2-Abbild für die Proxmox-VM 950 bauen (braucht disk_config/vm.toml).
set -euxo pipefail
cd "$(dirname "$0")/.."
IMAGE="${1:-localhost/pavlonya-os:44}"
test -f disk_config/vm.toml || { echo "disk_config/vm.toml fehlt (Vorlage: vm.toml.example)"; exit 1; }
mkdir -p output
[[ "${IMAGE}" == localhost/* ]] || sudo podman pull "${IMAGE}"
sudo podman run --rm -it --privileged --pull=newer \
    --security-opt label=type:unconfined_t \
    -v ./output:/output \
    -v /var/lib/containers/storage:/var/lib/containers/storage \
    -v ./disk_config/vm.toml:/config.toml:ro \
    quay.io/centos-bootc/bootc-image-builder:latest \
    --type qcow2 --rootfs xfs --chown "$(id -u):$(id -g)" \
    "${IMAGE}"
find output -name '*.qcow2' -exec ls -lh {} +
