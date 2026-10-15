#!/usr/bin/bash
# 90-cleanup.sh — Fremdquellen abschalten, Build-Reste entfernen.
set -euxo pipefail

# Fremdquellen aus: das laufende System bekommt Updates nur über neue Images
for f in /etc/yum.repos.d/rpmfusion-*.repo /etc/yum.repos.d/vscode.repo /etc/yum.repos.d/*nvidia*.repo; do
    [[ -f "$f" ]] && sed -i 's/^enabled=1/enabled=0/' "$f"
done

cat > /usr/lib/pavlonya-os-release <<REL
FEDORA_VERSION=${FEDORA_VERSION}
BUILD_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
KERNEL=$(rpm -q --qf '%{VERSION}-%{RELEASE}.%{ARCH}' kernel-core)
NVIDIA=$(rpm -q --qf '%{VERSION}' nvidia-driver)
REL

sed -i '/^excludepkgs=gdm,/d; /^install_weak_deps=False/d' /etc/dnf/dnf.conf
dnf -y clean all
rm -rf /build_files /packages /system_files /keys /tmp/nvidia
rm -rf /var/cache/* /var/log/* /var/tmp/* /tmp/* /run/* 2>/dev/null || true
cat /usr/lib/pavlonya-os-release
