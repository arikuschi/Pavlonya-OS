#!/usr/bin/bash
# startbild/build.sh — Bilder des Plymouth-Startbilds (Design „pavlonya“, two-step)
# und das Hintergrundbild für COSMIC.
#
# Läuft in einer eigenen Baustufe (Containerfile, Stufe „startbild“), damit weder
# der Renderer noch die Schrift fürs Rendern im Image landen. Ergebnis in /out,
# eingespielt von build_files/50-system.sh:
#   watermark.png   Logo mit Schriftzug aus startbild.svg — two-step setzt es je
#                   Bildschirm mittig, den Fortschrittsbalken zeichnet es selbst
#   entry.png …     Bilder für eine Kennwortabfrage; ohne sie lädt two-step das
#                   Design nicht. Aus Fedoras Standard-Design „spinner“, wie es auch
#                   Pop!_OS mitbringt
#   hintergrund/pavlonya-os.png   Hintergrundbild aus hintergrund.svg, 3840×2160 (4K-Monitor;
#                   aufs Laptop-Display skaliert COSMIC). Eigener Ordner, damit es nicht
#                   bei den Startbild-Dateien landet (50-system.sh kopiert /out/*.png)
set -euxo pipefail

dnf -y install librsvg2-tools open-sans-fonts plymouth-theme-spinner

# Schriftzug in Open Sans — ohne die Schrift nähme rsvg-convert still eine Ersatzschrift
fc-match "Open Sans:weight=600" | grep -Eqi "open ?sans"

mkdir -p /out
rsvg-convert -w 640 /startbild/startbild.svg -o /out/watermark.png
for f in entry bullet lock capslock keyboard keymap-render; do
    cp "/usr/share/plymouth/themes/spinner/${f}.png" /out/
done
mkdir -p /out/hintergrund
rsvg-convert -w 3840 -h 2160 /startbild/hintergrund.svg -o /out/hintergrund/pavlonya-os.png
ls -lR /out
