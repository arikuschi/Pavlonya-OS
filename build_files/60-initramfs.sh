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
for f in pavlonya.plymouth watermark.png entry.png; do
    if grep -q "themes/pavlonya/${f}" <<< "${INITRD}"; then
        echo "OK: Startbild ${f} in der initramfs"
    else
        echo "FEHLER: Startbild ${f} fehlt in der initramfs" >&2
        exit 1
    fi
done
# Ladereihenfolge amdgpu vor nvidia muss auch in der initramfs gelten
grep -q "usr/lib/modprobe.d/pavlonya-grafik.conf" <<< "${INITRD}" || {
    echo "FEHLER: pavlonya-grafik.conf fehlt in der initramfs" >&2; exit 1; }
for mod in nvidia amdgpu; do
    if grep -qE "/${mod}\.ko" <<< "${INITRD}"; then
        echo "OK: ${mod} in der initramfs"
    else
        echo "FEHLER: ${mod} fehlt in der initramfs" >&2
        exit 1
    fi
done
# Fremde Grafiktreiber machen die initramfs ~110 MB größer und GRUB ~4 s langsamer
# (dracut.conf.d/90-pavlonya-grafik.conf)
for mod in i915 xe nouveau radeon; do
    if grep -qE "/${mod}\.ko" <<< "${INITRD}"; then
        echo "FEHLER: ${mod} ist in der initramfs" >&2
        exit 1
    fi
    echo "OK: ${mod} nicht in der initramfs"
done
# Nur was der Laptop braucht (30.10.2026): AMD-Microcode ja, Intel nein;
# NVIDIA-Firmware für Ampere ja, für Turing nein
for f in AuthenticAMD.bin gsp_ga10x.bin; do
    grep -q "/${f}" <<< "${INITRD}" || { echo "FEHLER: ${f} fehlt in der initramfs" >&2; exit 1; }
done
for f in GenuineIntel.bin gsp_tu10x.bin ucodes_tu10x.bin; do
    if grep -q "/${f}" <<< "${INITRD}"; then
        echo "FEHLER: ${f} ist in der initramfs" >&2
        exit 1
    fi
done
head -1 <<< "${INITRD}"
