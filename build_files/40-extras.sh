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
dnf -y install "${URL}"

# Tabby installiert nach /opt/Tabby. Zeigt /opt (wie bei bootc üblich) auf
# /var/opt, landet es in /var — und /var wird nach der Installation nie mehr
# aus dem Image aktualisiert. Dann wandert Tabby nach /usr/lib/opt (Teil des
# Images) und /var/opt/Tabby wird beim Boot dorthin verlinkt.
ls -ld /opt
rpm -ql tabby-terminal | grep -E "/tabby$" | head -5   # Diagnose: wo liegt das Programm?
TABBY="$(readlink -f /opt/Tabby)"
echo "Tabby liegt in ${TABBY}"
test -x "${TABBY}/tabby"
if [[ "${TABBY}" == /var/* ]]; then
    mkdir -p /usr/lib/opt
    mv "${TABBY}" /usr/lib/opt/Tabby
    cat > /usr/lib/tmpfiles.d/pavlonya-tabby.conf <<'TMP'
d /var/opt 0755 root root -
L+ /var/opt/Tabby - - - - /usr/lib/opt/Tabby
TMP
fi
