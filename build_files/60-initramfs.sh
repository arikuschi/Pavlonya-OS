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

# Prüfen statt nur anzeigen: beide Grafiktreiber müssen in der initramfs sein,
# sonst bleibt der HDMI-Ausgang (hängt an der NVIDIA) beim Start schwarz.
INITRD="$(lsinitrd "/usr/lib/modules/${KVER}/initramfs.img")"
# Startbild: ohne Design in der initramfs zeigt Plymouth beim Start nur Text
for f in pavlonya.script startbild.png; do
    if grep -q "themes/pavlonya/${f}" <<< "${INITRD}"; then
        echo "OK: Startbild ${f} in der initramfs"
    else
        echo "FEHLER: Startbild ${f} fehlt in der initramfs" >&2
        exit 1
    fi
done
for mod in nvidia amdgpu; do
    if grep -qE "/${mod}\.ko" <<< "${INITRD}"; then
        echo "OK: ${mod} in der initramfs"
    else
        echo "FEHLER: ${mod} fehlt in der initramfs" >&2
        exit 1
    fi
done
