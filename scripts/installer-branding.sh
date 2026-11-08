#!/usr/bin/bash
# Installer der ISO als „Pavlonya OS“ statt Fedora — Ablauf in disk_config/installer/branding.sh.
#   sudo scripts/installer-branding.sh output/pavlonya-os-45.iso 45
# Root nötig: mkksiso baut efiboot.img mit mkefiboot neu (Schleifengerät).
set -euo pipefail
cd "$(dirname "$0")/.."
ISO="$(realpath "$1")"; VER="${2:?Fedora-Version angeben, z. B. 45}"
podman run --rm --privileged --security-opt label=type:unconfined_t \
    -v ./disk_config/installer:/src:ro -v "$(dirname "${ISO}"):/work" \
    -v ./system_files/usr/share/icons/hicolor/scalable/apps/pavlonya-os.svg:/logo.svg:ro \
    "registry.fedoraproject.org/fedora:${VER}" \
    /src/branding.sh "/work/$(basename "${ISO}")" "${VER}"
ls -lh "${ISO}"
