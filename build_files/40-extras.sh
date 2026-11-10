#!/usr/bin/bash
# 40-extras.sh — Programme ohne Fedora-Paket.
set -euxo pipefail

# --- Tabby (Terminal/SSH-Client) ---------------------------------------------
# Kein Fedora-Paket; RPM aus dem GitHub-Release. Version und SHA-256 stehen hier
# fest: Das RPM ist nicht signiert, und seine Installationsskripte laufen im Bau
# als root — ohne Prüfung käme ein ausgetauschtes Release signiert auf den Laptop.
# Neue Version: beide Zeilen ändern. Die Prüfsumme steht auf der Release-Seite
# neben der Datei, oder:
#   gh api repos/Eugeny/tabby/releases/latest \
#     --jq '.tag_name, (.assets[] | select(.name | endswith("linux-x64.rpm")) | .digest)'
TABBY_VERSION="1.0.238"
TABBY_SHA256="d5027a5f905edf40aaf1fd42ef5015abfaffbd96f5825b3622ef352dfc3136b3"
URL="https://github.com/Eugeny/tabby/releases/download/v${TABBY_VERSION}/tabby-${TABBY_VERSION}-linux-x64.rpm"
curl -fsSL --retry 3 -o /tmp/tabby.rpm "${URL}"
echo "${TABBY_SHA256}  /tmp/tabby.rpm" | sha256sum -c -
dnf -y install /tmp/tabby.rpm
rm -f /tmp/tabby.rpm

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
