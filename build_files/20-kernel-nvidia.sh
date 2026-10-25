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
# Nur die Laufzeit-Pakete — kernel-devel und kernel-uki-virt aus dem Cache
# zögen gut 90 weitere Pakete (Compiler, qemu-img) ins Image.
KPKGS=()
for name in kernel kernel-core kernel-modules kernel-modules-core kernel-modules-extra; do
    KPKGS+=("${SRC}"/kernel-rpms/"${name}"-[0-9]*.rpm)
done
dnf -y install "${KPKGS[@]}"

for h in 05-rpmostree.install 50-dracut.install; do
    if [[ -f "${HOOKS}/${h}.bak" ]]; then
        mv -f "${HOOKS}/${h}.bak" "${HOOKS}/${h}"
    fi
done

# shellcheck disable=SC1091
source "${SRC}/rpms/kmods/nvidia-vars"   # KERNEL_VERSION, NVIDIA_AKMOD_VERSION, DIST_ARCH

# Reste des Basis-Kernels entfernen: initramfs und vmlinuz unter
# /usr/lib/modules/<version> gehören keinem Paket und bleiben nach dem
# dnf remove liegen, wenn das Basis-Image einen anderen Kernel hat als der
# akmods-Cache (12.10.2026: Basis 7.2.9-201, Cache 7.2.9-200).
for dir in /usr/lib/modules/*; do
    if [[ "$(basename "${dir}")" != "${KERNEL_VERSION}" ]]; then
        echo "### Entferne Rest des Basis-Kernels: ${dir}"
        rm -rf "${dir}"
    fi
done

dnf -y install "${SRC}"/rpms/ublue-os/ublue-os-nvidia-addons-*.rpm
# negativo17-Quelle (aus dem Addon) nur für diesen Aufruf, für die 32-Bit-Bibliotheken
dnf -y install --enablerepo='fedora-nvidia*' \
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

# NVIDIA und amdgpu in die initramfs mitnehmen (sonst bleibt der HDMI-Ausgang an
# der dGPU beim Start schwarz), aber NICHT erzwingen (25.10.2026): erzwungene
# Treiber lädt dracut nacheinander vor allem anderen — der NVIDIA-Treiber braucht
# gut 7 s, das Startbild erschien erst danach. Mitgenommen lädt udev sie nebenher,
# Plymouth zeichnet sofort über den Bildspeicher der Firmware (simpledrm), wie
# Pop!_OS über efifb. Reihenfolge amdgpu vor nvidia: modprobe.d/pavlonya-grafik.conf.
NVCONF=/usr/lib/dracut/dracut.conf.d/99-nvidia.conf
if [[ -f "${NVCONF}" ]]; then
    sed -i 's@omit_drivers@add_drivers@g; s@force_drivers@add_drivers@g; s@ nvidia @ amdgpu nvidia @g' "${NVCONF}"
    cat "${NVCONF}"
    grep -q 'add_drivers.* amdgpu nvidia ' "${NVCONF}"
    if grep -Eq 'force_drivers|omit_drivers' "${NVCONF}"; then
        echo "FEHLER: ${NVCONF} erzwingt oder unterdrückt noch Treiber" >&2
        exit 1
    fi
fi
