#!/usr/bin/bash
# 10-repos.sh — Paketquellen außerhalb von Fedora.
#
# Alle Quellen werden nach dem Build wieder abgeschaltet (90-cleanup.sh).
# Updates kommen ausschließlich über ein neues Image, nicht über dnf.
set -euxo pipefail

FEDORA="$(rpm -E %fedora)"

# --- Fedora-Grundbestand ausdünnen (15.10.2026: schlank) -------------
# Aus fedora-bootc, auf diesem Laptop ohne Nutzen (geprüft am Gerät):
#   python3-boto3/-botocore  AWS-Werkzeuge für Cloud-Server (~130 MB)
#   toolbox                  doppelt zu distrobox
#   sos                      Red-Hat-Supportberichte
#   ModemManager, libqmi, libmbim, NetworkManager-wwan   Mobilfunkmodem (keins verbaut)
#   sg3_utils                SCSI-Werkzeuge
#   Firmware fremder Hardware: Atheros, Broadcom, TI, NXP, Realtek (WLAN/BT ist
#   MediaTek, LAN-Firmware liegt in linux-firmware), Intel-Grafik/-Audio/-NPU,
#   Cirrus-Audio, Qualcomm-WWAN
BASIS_RAUS=(
    python3-boto3 python3-botocore toolbox sos sg3_utils
    ModemManager libqmi libmbim NetworkManager-wwan
    atheros-firmware brcmfmac-firmware tiwilink-firmware nxpwireless-firmware realtek-firmware
    intel-gpu-firmware intel-audio-firmware intel-npu-firmware cirrus-audio-firmware qcom-wwan-firmware
)
dnf -y remove --no-autoremove "${BASIS_RAUS[@]}"

# Kein GNOME-Desktop im Image: kam nur als empfohlenes Zusatzpaket mit (GNOME Shell,
# GDM, Systemeinstellungen, Rygel — Laptop 15.10.2026). Für alle Bau-Schritte
# ausgeschlossen; braucht ein Paket eines davon zwingend, bricht der Bau ab und
# nennt es. 90-cleanup.sh nimmt den Ausschluss wieder heraus.
echo "excludepkgs=gdm,gnome-shell,gnome-shell-extension-*,gnome-session,gnome-session-*,gnome-control-center,mutter,rygel,$(IFS=,; echo "${BASIS_RAUS[*]}")" >> /etc/dnf/dnf.conf

# Grundsätzlich KEINE Empfehlungen (weak dependencies) installieren — sie brachten
# 223 Pakete / ~1 GB ungenutzt mit (Messung 15.10.2026). Was davon gebraucht wird,
# steht ausdrücklich in packages/60-bewusst-aus-empfehlungen.txt.
echo "install_weak_deps=False" >> /etc/dnf/dnf.conf

# RPM Fusion — für Steam (nonfree)
# Die Release-Pakete direkt vom Hauptserver: Der Verteiler mirrors.rpmfusion.org
# schickte die GitHub-Runner am 20.10.2026 auf einen toten Spiegel
# (repos.eggycrew.com), der Bau brach ab. Die Pakete selbst kommen danach über
# die Spiegelliste der Quelle, dort probiert dnf mehrere Spiegel durch.
dnf -y install \
    "https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA}.noarch.rpm" \
    "https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FEDORA}.noarch.rpm"

# Visual Studio Code — offizielles Microsoft-Repo
rpm --import https://packages.microsoft.com/keys/microsoft.asc
cat > /etc/yum.repos.d/vscode.repo <<'REPO'
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
REPO
