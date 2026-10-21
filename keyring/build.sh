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

# Patch-Zeile nach der ersten Source-Zeile einfügen; %autosetup -p1 wendet sie an.
grep -Eq '^%autosetup.*-p1' "${SPEC}" || {
    echo "FEHLER: gnome-keyring.spec nutzt kein '%autosetup -p1' — Patch würde nicht angewendet" >&2
    exit 1
}
awk '!eingefuegt && /^Source[0-9]*:/ { print; print "Patch9001: opensession-fix.patch"; eingefuegt = 1; next } { print }' \
    "${SPEC}" > "${SPEC}.neu"
mv "${SPEC}.neu" "${SPEC}"
grep -n -E '^(Name|Version|Release|Source[0-9]*|Patch[0-9]*):' "${SPEC}"

dnf -y builddep "${SPEC}"
rpmbuild -bb --nocheck \
    --define "_topdir ${TOP}" \
    --define "dist .fc$(rpm -E %fedora).pavlonya" \
    "${SPEC}"

mkdir -p /out
cp "${TOP}"/RPMS/x86_64/gnome-keyring-[0-9]*.rpm \
   "${TOP}"/RPMS/x86_64/gnome-keyring-pam-[0-9]*.rpm /out/
ls -l /out
