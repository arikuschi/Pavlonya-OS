#!/usr/bin/bash
# 10-repos.sh — Paketquellen außerhalb von Fedora.
#
# Alle Quellen werden nach dem Build wieder abgeschaltet (90-cleanup.sh).
# Updates kommen ausschließlich über ein neues Image, nicht über dnf.
set -euxo pipefail

FEDORA="$(rpm -E %fedora)"

# Kein GNOME-Desktop im Image: kam nur als empfohlenes Zusatzpaket mit (GNOME Shell,
# GDM, Systemeinstellungen, Rygel — Laptop 15.10.2026). Für alle Bau-Schritte
# ausgeschlossen; braucht ein Paket eines davon zwingend, bricht der Bau ab und
# nennt es. 90-cleanup.sh nimmt den Ausschluss wieder heraus.
echo "excludepkgs=gdm,gnome-shell,gnome-shell-extension-*,gnome-session,gnome-session-*,gnome-control-center,mutter,rygel" >> /etc/dnf/dnf.conf

# Grundsätzlich KEINE Empfehlungen (weak dependencies) installieren — sie brachten
# 223 Pakete / ~1 GB ungenutzt mit (Messung 15.10.2026). Was davon gebraucht wird,
# steht ausdrücklich in packages/60-bewusst-aus-empfehlungen.txt.
echo "install_weak_deps=False" >> /etc/dnf/dnf.conf

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
