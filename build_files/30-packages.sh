#!/usr/bin/bash
# 30-packages.sh — alle Paketlisten aus packages/*.txt installieren.
#
# Ein Paket pro Zeile, alles ab '#' ist Kommentar. Bewusst ohne
# --skip-unavailable: ein falscher Name bricht den Build ab.
set -euo pipefail

PKGS=()
for list in /packages/*.txt; do
    mapfile -t entries < <(sed -E 's/#.*$//; s/^[[:space:]]+//; s/[[:space:]]+$//; /^$/d' "${list}")
    echo "### ${list##*/}: ${#entries[@]} Pakete"
    PKGS+=("${entries[@]}")
done

set -x
dnf -y install --exclude=dracut-config-rescue "${PKGS[@]}"
