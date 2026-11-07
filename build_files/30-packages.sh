#!/usr/bin/bash
# 30-packages.sh — alle Paketlisten aus packages/*.txt installieren.
#
# Ein Paket pro Zeile, alles ab '#' ist Kommentar. Bewusst ohne
# --skip-unavailable: ein falscher Name bricht den Build ab.
# „paket [bis 44]“: nur bis zu dieser Fedora-Version — für Pakete, die eine
# neuere Version abgeschafft hat, solange beide Versionen gebaut werden.
set -euo pipefail

FEDORA="$(rpm -E %fedora)"
PKGS=()
for list in /packages/*.txt; do
    mapfile -t entries < <(sed -E 's/#.*$//; s/^[[:space:]]+//; s/[[:space:]]+$//; /^$/d' "${list}")
    n=0
    for e in "${entries[@]}"; do
        if [[ "${e}" =~ ^([^[:space:]]+)[[:space:]]+\[bis[[:space:]]+([0-9]+)\]$ ]]; then
            if (( FEDORA > BASH_REMATCH[2] )); then
                echo "ausgelassen (Fedora ${FEDORA}): ${BASH_REMATCH[1]}"
                continue
            fi
            e="${BASH_REMATCH[1]}"
        fi
        PKGS+=("${e}"); n=$((n + 1))
    done
    echo "### ${list##*/}: ${n} Pakete"
done

set -x
dnf -y install --exclude=dracut-config-rescue "${PKGS[@]}"
