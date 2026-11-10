#!/usr/bin/bash
# Installations-ISO bauen. Standard: das lokal gebaute Image.
#   scripts/build-iso.sh                                  # localhost/pavlonya-os:45
#   scripts/build-iso.sh ghcr.io/<name>/pavlonya-os:45    # Image von GitHub
# Danach bekommt der Installer Namen und Logo von Pavlonya OS (installer-branding.sh).
set -euxo pipefail
cd "$(dirname "$0")/.."
IMAGE="${1:-localhost/pavlonya-os:45}"
mkdir -p output
[[ "${IMAGE}" == localhost/* ]] || sudo podman pull "${IMAGE}"
# Fedora-Version aus dem Image (Label „45.20261107.0“ → 45) — vor dem langen Bau, solange
# sudo noch nicht wieder nach dem Kennwort fragt
VER="$(sudo podman inspect --format '{{index .Labels "org.opencontainers.image.version"}}' "${IMAGE}" | cut -d. -f1)"
[[ -n "${VER}" ]]
sudo podman run --rm -it --privileged --pull=newer \
    --security-opt label=type:unconfined_t \
    -v ./output:/output \
    -v /var/lib/containers/storage:/var/lib/containers/storage \
    -v ./disk_config/iso.toml:/config.toml:ro \
    quay.io/centos-bootc/bootc-image-builder:latest \
    --type anaconda-iso --rootfs btrfs --chown "$(id -u):$(id -g)" \
    "${IMAGE}"
# bootc-image-builder nennt die Datei immer install.iso — hier sprechend
# umbenennen: pavlonya-os-<tag>.iso (Tag aus dem Image, z. B. 45)
TAG="${IMAGE##*:}"
mv -f output/bootiso/install.iso "output/pavlonya-os-${TAG}.iso"
rm -rf output/bootiso
# Fragt sudo hier nach dem Kennwort und läuft die Zeit ab, fehlt nur das Branding — nachholen mit
#   sudo scripts/installer-branding.sh output/pavlonya-os-<tag>.iso <version>
sudo scripts/installer-branding.sh "output/pavlonya-os-${TAG}.iso" "${VER}"
