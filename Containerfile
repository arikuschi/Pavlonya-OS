# Pavlonya OS — Fedora-Atomic-Image (bootc) für den Acer Nitro AN517-41
#
#   CPU/iGPU : AMD Ryzen 7 5800H / Cezanne [1002:1638]  -> amdgpu
#   dGPU     : NVIDIA RTX 3070 Mobile      [10de:249d]  -> nvidia-open
#   WLAN/BT  : MediaTek MT7921             [14c3:7961]  -> mt7921e
#
# Aufbau: README.md. Paketlisten: packages/*.txt. Flatpaks:
# system_files/usr/share/pavlonya-os/flatpaks.txt

ARG FEDORA_VERSION=44
ARG KERNEL_FLAVOR=main

# Vorgebaute nvidia-open-Module samt passendem Kernel (Universal Blue)
FROM ghcr.io/ublue-os/akmods-nvidia-open:${KERNEL_FLAVOR}-${FEDORA_VERSION} AS nvidia

FROM quay.io/fedora/fedora-bootc:${FEDORA_VERSION}

ARG FEDORA_VERSION
# Wird in policy.json eingetragen; der Workflow setzt den echten Namen.
ARG IMAGE_REF=ghcr.io/CHANGEME/pavlonya-os

COPY build_files /build_files
COPY packages /packages
COPY system_files /system_files
COPY keys /keys
COPY --from=nvidia / /tmp/nvidia

RUN --mount=type=cache,dst=/var/cache/libdnf5 /build_files/10-repos.sh
RUN --mount=type=cache,dst=/var/cache/libdnf5 /build_files/20-kernel-nvidia.sh
RUN --mount=type=cache,dst=/var/cache/libdnf5 /build_files/30-packages.sh
RUN --mount=type=cache,dst=/var/cache/libdnf5 /build_files/40-extras.sh
RUN IMAGE_REF="${IMAGE_REF}" /build_files/50-system.sh
RUN /build_files/60-initramfs.sh
RUN FEDORA_VERSION="${FEDORA_VERSION}" /build_files/90-cleanup.sh

LABEL containers.bootc=1
LABEL org.opencontainers.image.title="pavlonya-os"
LABEL org.opencontainers.image.description="Fedora Atomic mit COSMIC für den Acer Nitro AN517-41"

RUN bootc container lint
