#!/usr/bin/bash
# 40-extras.sh — Programme ohne Fedora-Paket.
set -euxo pipefail

# --- Tabby (Terminal/SSH-Client) ---------------------------------------------
# Kein Fedora-Paket; RPM aus dem neuesten GitHub-Release.
URL="$(curl -fsSL https://api.github.com/repos/Eugeny/tabby/releases/latest \
    | grep -oE '"browser_download_url": *"[^"]*linux-x64\.rpm"' \
    | sed -E 's/.*"(https[^"]+)"/\1/' | head -1)"
if [[ -z "${URL}" ]]; then
    echo "FEHLER: Tabby-RPM im neuesten Release nicht gefunden" >&2
    exit 1
fi
mkdir -p /var/opt
dnf -y install "${URL}"

# Tabby installiert nach /opt. /opt zeigt bei bootc auf /var/opt, und /var wird
# nach der Installation nie mehr aus dem Image aktualisiert. Deshalb wandert
# Tabby nach /usr (Teil des Images); /var/opt/Tabby wird beim Boot verlinkt
# (system_files/usr/lib/tmpfiles.d/pavlonya-os.conf).
mkdir -p /usr/lib/opt
mv /var/opt/Tabby /usr/lib/opt/Tabby
