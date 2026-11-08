#!/usr/bin/bash
# 90-cleanup.sh — Fremdquellen abschalten, Build-Reste entfernen.
set -euxo pipefail

# Fremdquellen aus: das laufende System bekommt Updates nur über neue Images.
# Repo-Dateien liegen bis Fedora 44 unter /etc/yum.repos.d, ab 45 unter
# /usr/share/dnf5/repos.d (RPM Fusion ebenso) — beide Ordner.
shopt -s nullglob
for d in /etc/yum.repos.d /usr/share/dnf5/repos.d; do
    for f in "$d"/rpmfusion-*.repo "$d"/vscode*.repo "$d"/*nvidia*.repo; do
        sed -i 's/^enabled=1/enabled=0/' "$f"
    done
done
# bootc-image-builder liest für den Installer der ISO nur /etc/yum.repos.d — ohne
# Fedora-Quellen dort bricht er ab („no enabled repositories“, Fedora 45, 08.11.2026).
# Gleicher Inhalt; dnf nimmt bei gleichem Namen die Datei aus /etc.
for f in /usr/share/dnf5/repos.d/fedora*.repo; do
    [[ -e "/etc/yum.repos.d/${f##*/}" ]] || cp -a "$f" /etc/yum.repos.d/
done
if grep -qs '^enabled=1' /etc/yum.repos.d/rpmfusion-*.repo /etc/yum.repos.d/vscode.repo /etc/yum.repos.d/*nvidia*.repo \
        /usr/share/dnf5/repos.d/rpmfusion-*.repo /usr/share/dnf5/repos.d/*nvidia*.repo; then exit 1; fi
shopt -u nullglob
grep -q '^enabled=1' /etc/yum.repos.d/fedora.repo

# /usr/local/sbin fehlt im bootc-Grundabbild; die tmpfiles-Regel von rpm-ostree will es
# anlegen und meldet bei jedem Start „Read-only file system“. Ordner, kein Verweis auf bin:
# den lehnt dieselbe Regel mit „is not a directory“ ab (im Container getestet).
mkdir -p /usr/local/sbin

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
