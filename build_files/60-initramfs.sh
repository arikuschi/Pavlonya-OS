#!/usr/bin/bash
# 60-initramfs.sh — initramfs neu bauen, nachdem Kernel und NVIDIA drin sind.
set -euxo pipefail

KVERS=(/usr/lib/modules/*)
if [[ ${#KVERS[@]} -ne 1 ]]; then
    echo "FEHLER: erwartet genau einen Kernel, gefunden: ${KVERS[*]}" >&2
    exit 1
fi
KVER="$(basename "${KVERS[0]}")"

export DRACUT_NO_XATTR=1
dracut --no-hostonly --kver "${KVER}" --reproducible --zstd -v --add ostree \
    -f "/usr/lib/modules/${KVER}/initramfs.img"

lsinitrd "/usr/lib/modules/${KVER}/initramfs.img" | grep -E 'nvidia|amdgpu' | head
