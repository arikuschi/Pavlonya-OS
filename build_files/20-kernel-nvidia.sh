#!/usr/bin/bash
# 20-kernel-nvidia.sh — Kernel und nvidia-open aus dem akmods-Image.
#
# Das Kernelmodul muss exakt zum Kernel passen. Das akmods-Image von Universal
# Blue liefert beides zusammen: die Kernel-RPMs und die dagegen gebauten,
# signierten kmods. Deshalb wird der Kernel des Basis-Images ersetzt.
#
# Layout des akmods-Images:
#   /kernel-rpms/     kernel, kernel-core, kernel-modules, ...
#   /rpms/kmods/      kmod-nvidia-<kernel>-<treiber>.rpm, nvidia-vars
#   /rpms/nvidia/     Userspace-RPMs (x86_64, noarch)
#   /rpms/ublue-os/   ublue-os-nvidia-addons (Repo-Definition negativo17, MOK-Schlüssel)
set -euxo pipefail

SRC=/tmp/nvidia

# kernel-install-Hooks während des Tauschs stilllegen; die initramfs wird
# einmal am Ende gebaut (60-initramfs.sh), wenn alle Module drin sind.
HOOKS=/usr/lib/kernel/install.d
for h in 05-rpmostree.install 50-dracut.install; do
    if [[ -f "${HOOKS}/${h}" ]]; then
        mv "${HOOKS}/${h}" "${HOOKS}/${h}.bak"
        printf '#!/bin/sh\nexit 0\n' > "${HOOKS}/${h}"
        chmod +x "${HOOKS}/${h}"
    fi
done

dnf -y remove --no-autoremove \
    kernel kernel-core kernel-modules kernel-modules-core kernel-modules-extra
dnf -y install "${SRC}"/kernel-rpms/*.rpm

for h in 05-rpmostree.install 50-dracut.install; do
    if [[ -f "${HOOKS}/${h}.bak" ]]; then
        mv -f "${HOOKS}/${h}.bak" "${HOOKS}/${h}"
    fi
done

# shellcheck disable=SC1091
source "${SRC}/rpms/kmods/nvidia-vars"   # KERNEL_VERSION, NVIDIA_AKMOD_VERSION, DIST_ARCH

dnf -y install "${SRC}"/rpms/ublue-os/ublue-os-nvidia-addons-*.rpm
dnf config-manager setopt "fedora-nvidia*".enabled=1

dnf -y install \
    "${SRC}"/rpms/nvidia/*.x86_64.rpm \
    "${SRC}"/rpms/nvidia/*.noarch.rpm \
    "${SRC}/rpms/kmods/kmod-nvidia-${KERNEL_VERSION}-${NVIDIA_AKMOD_VERSION}.${DIST_ARCH}.rpm" \
    nvidia-driver-libs.i686 \
    egl-wayland \
    libva-nvidia-driver

# Modul, Treiber und 32-Bit-Bibliotheken müssen dieselbe Version haben —
# sonst schwarzer Bildschirm bzw. Steam-Spiele ohne dGPU.
KMOD="$(rpm -q --qf '%{VERSION}' kmod-nvidia)"
DRV="$(rpm -q --qf '%{VERSION}' nvidia-driver)"
LIB32="$(rpm -q --qf '%{VERSION}' nvidia-driver-libs.i686)"
if [[ "${KMOD}" != "${DRV}" || "${DRV}" != "${LIB32}" ]]; then
    echo "FEHLER: kmod ${KMOD} / Treiber ${DRV} / 32 Bit ${LIB32} passen nicht zusammen" >&2
    exit 1
fi

# NVIDIA und amdgpu früh laden; sonst schwarzer Bildschirm am HDMI (hängt an der dGPU)
if [[ -f /usr/lib/dracut/dracut.conf.d/99-nvidia.conf ]]; then
    sed -i 's@omit_drivers@force_drivers@g; s@ nvidia @ amdgpu nvidia @g' \
        /usr/lib/dracut/dracut.conf.d/99-nvidia.conf
fi
