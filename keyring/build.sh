#!/usr/bin/bash
# keyring/build.sh — gnome-keyring aus Fedoras Quellpaket neu bauen, mit dem
# Fix aus opensession-fix.patch (gnome-keyring #190, MR !112).
#
# Grund: gnome-keyring 50.0 bricht ab (SIGABRT), wenn ein Programm viele
# Verbindungen gleichzeitig öffnet — Zed beim Öffnen eines Projekts, der
# Codex-Dienst von ChatGPT. Der danach von D-Bus gestartete Daemon kennt das
# Anmeldekennwort nicht, der Schlüsselbund ist gesperrt und Programme fragen
# nach dem Kennwort. Pop!_OS (gnome-keyring 46) war nicht betroffen.
#
# Läuft in einer eigenen Baustufe (Containerfile, Stufe „keyring“); die fertigen
# RPMs landen in /out und werden von build_files/45-keyring.sh eingespielt.
# Das Release bekommt den Zusatz „.pavlonya“, damit es neuer ist als Fedoras
# Paket und sich im Image erkennen lässt.
#
# Enthält Fedoras Paket den Fix eines Tages selbst, passt der Patch nicht mehr
# und der Bau bricht hier ab — dann diese Stufe wieder ausbauen.
set -euxo pipefail

# dnf5: Quellpaket mit --srpm, builddep kommt aus dnf5-plugins
dnf -y install rpm-build dnf5-plugins

TOP=/rpmbuild
mkdir -p /src "${TOP}"
cd /src
dnf -y download --srpm gnome-keyring
ls -l gnome-keyring-*.src.rpm
rpm -i --define "_topdir ${TOP}" gnome-keyring-*.src.rpm

SPEC="${TOP}/SPECS/gnome-keyring.spec"
cp /keyring/opensession-fix.patch "${TOP}/SOURCES/"

# %autosetup muss die Patches anwenden, und zwar mit -p1: Fedora nutzt
# „%autosetup -S git“ (git apply, Vorgabe -p1); ohne -S braucht es „-p1“.
# Mit -N würden gar keine Patches angewendet.
SETUP="$(grep -E '^%autosetup' "${SPEC}" || true)"
if [[ -z "${SETUP}" || "${SETUP}" =~ [[:space:]]-N([[:space:]]|$) ]] \
   || ! [[ "${SETUP}" =~ -S[[:space:]]*git || "${SETUP}" =~ -p1 ]]; then
    echo "FEHLER: unerwartete Zeile in gnome-keyring.spec: '${SETUP}' — Patch würde nicht angewendet" >&2
    exit 1
fi
# Patch-Zeile hinter Fedoras letzte Patch-Zeile (sonst hinter die erste
# Source-Zeile): höhere Nummer, also wird unser Patch zuletzt angewendet.
if grep -Eq '^Patch[0-9]*:' "${SPEC}"; then MUSTER='^Patch[0-9]*:'; else MUSTER='^Source[0-9]*:'; fi
ZEILE="$(grep -En "${MUSTER}" "${SPEC}" | { if [[ "${MUSTER}" == '^Patch[0-9]*:' ]]; then tail -1; else head -1; fi; } | cut -d: -f1)"
sed -i "${ZEILE}a Patch9001: opensession-fix.patch" "${SPEC}"
grep -n -E '^(Name|Version|Release|Source[0-9]*|Patch[0-9]*):|^%autosetup' "${SPEC}"

dnf -y builddep "${SPEC}"
rpmbuild -bb --nocheck \
    --define "_topdir ${TOP}" \
    --define "dist .fc$(rpm -E %fedora).pavlonya" \
    "${SPEC}"

mkdir -p /out
cp "${TOP}"/RPMS/x86_64/gnome-keyring-[0-9]*.rpm \
   "${TOP}"/RPMS/x86_64/gnome-keyring-pam-[0-9]*.rpm /out/
ls -l /out
