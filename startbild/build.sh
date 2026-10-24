#!/usr/bin/bash
# startbild/build.sh — Bilder des Plymouth-Startbilds aus den SVG-Quellen rendern.
#
# Läuft in einer eigenen Baustufe (Containerfile, Stufe „startbild“), damit weder
# der Renderer noch die Schrift fürs Rendern im Image landen. Die PNGs kommen nach
# /out und werden von build_files/50-system.sh ins Plymouth-Design gelegt.
# Doppelte Auflösung: das Skript verkleinert passend zum Bildschirm.
set -euxo pipefail

dnf -y install librsvg2-tools open-sans-fonts

# Schriftzug in Open Sans — ohne die Schrift nähme rsvg-convert still eine Ersatzschrift
fc-match "Open Sans:weight=600" | grep -Eqi "open ?sans"

mkdir -p /out
rsvg-convert -w 1600 /startbild/startbild.svg -o /out/startbild.png
rsvg-convert -w 800 /startbild/balken-hinten.svg -o /out/balken-hinten.png
rsvg-convert -w 800 /startbild/balken-vorne.svg -o /out/balken-vorne.png
ls -l /out
