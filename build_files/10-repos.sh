#!/usr/bin/bash
# 10-repos.sh — Paketquellen außerhalb von Fedora.
#
# Alle Quellen werden nach dem Build wieder abgeschaltet (90-cleanup.sh).
# Updates kommen ausschließlich über ein neues Image, nicht über dnf.
set -euxo pipefail

FEDORA="$(rpm -E %fedora)"

# RPM Fusion — für Steam (nonfree)
dnf -y install \
    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA}.noarch.rpm" \
    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FEDORA}.noarch.rpm"

# Visual Studio Code — offizielles Microsoft-Repo
rpm --import https://packages.microsoft.com/keys/microsoft.asc
cat > /etc/yum.repos.d/vscode.repo <<'REPO'
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
REPO
