#!/usr/bin/bash
# branding.sh — Installer der ISO als „Pavlonya OS“ statt Fedora (Arikushi, 07.11.2026).
# Läuft in einem Fedora-Container, gestartet von scripts/installer-branding.sh.
#
# bootc-image-builder baut den Installer aus Fedora-Paketen (fedora-logos,
# fedora-release): Seitenleiste mit Fedora-Logo, Fedora-Symbole, Datenträger
# „Fedora-S-dvd-…“, Startmeldungen „Fedora Linux“. Bootmenü und Titel nennen schon
# „Pavlonya OS“ (Produktname aus dem Image).
#
# Abhilfe auf dem von Anaconda vorgesehenen Weg: images/product.img (cpio, gzip) —
# Anaconda legt ihren Inhalt beim Start über das Installer-System. Dazu mit mkksiso
# den Datenträgernamen ändern. „quiet“ setzt bootc-image-builder selbst; die Meldungen
# der initramfs („Fedora Linux … dracut“) erreicht die product.img nicht.
set -euo pipefail
ISO="$1"; VER="$2"
SRC=/src

dnf -y -q install lorax squashfs-tools librsvg2-tools open-sans-fonts cpio gzip >/dev/null 2>&1
fc-match "Open Sans:weight=600" | grep -Eqi "open ?sans"   # sonst Ersatzschrift ohne Meldung

T=$(mktemp -d)
cd "$T"
osirrox -indev "$ISO" -extract /images/install.img install.img >/dev/null 2>&1
unsquashfs -q -no-xattrs -d orig install.img usr/lib/os-release usr/share/anaconda/pixmaps/fedora.css >/dev/null
P=produkt
PIX=$P/usr/share/anaconda/pixmaps
mkdir -p "$PIX" $P/usr/lib

# Farben und Hintergründe: Verlauf Cyan → Blau wie Logo und Startbild
css=orig/usr/share/anaconda/pixmaps/fedora.css
for s in "@define-color fedora #51a2da;" \
         "background-image: url('/usr/share/anaconda/pixmaps/sidebar-bg.png');" \
         "background-image: url('/usr/share/anaconda/pixmaps/topbar-bg.png');"; do
    grep -qF "$s" "$css" || { echo "FEHLER: fedora.css hat sich geändert, fehlt: $s" >&2; exit 1; }
done
sed -e 's|@define-color fedora #51a2da;|@define-color fedora #4a5bd4;|' \
    -e "s|background-image: url('/usr/share/anaconda/pixmaps/sidebar-bg.png');|background-image: linear-gradient(to bottom right, #3cc6d6, #4a5bd4);|" \
    -e "s|background-image: url('/usr/share/anaconda/pixmaps/topbar-bg.png');|background-image: linear-gradient(to right, #3cc6d6, #4a5bd4);|" \
    "$css" > "$PIX/fedora.css"
rsvg-convert -w 150 -h 69 "$SRC/sidebar-logo.svg" -o "$PIX/sidebar-logo.png"

# Symbole: Fedora-Logo und Anaconda-Symbol durch das Pavlonya-Logo ersetzen
for s in 16 22 24 32 36 48 96 256; do
    d=$P/usr/share/icons/hicolor/${s}x${s}/apps; mkdir -p "$d"
    rsvg-convert -w $s -h $s /logo.svg -o "$d/fedora-logo-icon.png"
done
cp $P/usr/share/icons/hicolor/256x256/apps/fedora-logo-icon.png $P/usr/share/icons/hicolor/256x256/apps/anaconda.png
mkdir -p $P/usr/share/icons/hicolor/scalable/apps
cp /logo.svg $P/usr/share/icons/hicolor/scalable/apps/org.fedoraproject.AnacondaInstaller.svg

# Name des Installer-Systems; ID=fedora bleibt (Anaconda wählt daran ihr Profil)
grep -q '^ID=fedora$' orig/usr/lib/os-release
sed -e 's|^NAME=.*|NAME="Pavlonya OS"|' -e "s|^PRETTY_NAME=.*|PRETTY_NAME=\"Pavlonya OS ${VER}\"|" \
    orig/usr/lib/os-release > $P/usr/lib/os-release

mkdir -p images
(cd $P && find . | cpio -o -H newc --quiet | gzip -9) > images/product.img
echo "product.img:"; zcat images/product.img | cpio -it --quiet | sort

mkksiso -a images -V "Pavlonya-OS-${VER}" "$ISO" neu.iso
chown --reference="$ISO" neu.iso   # Besitzer wie vorher, nicht root
mv -f neu.iso "$ISO"
rm -rf "$T"
