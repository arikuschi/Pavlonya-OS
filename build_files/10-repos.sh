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
# Prüfung gegen die Hardware (30.10.2026: nur was der Laptop braucht):
#   nvidia-gpu-firmware      Firmware für nouveau (~106 MB); der NVIDIA-Treiber bringt eigene mit
#   microcode_ctl            Microcode für Intel-CPUs; der Laptop hat eine AMD-CPU
#   qemu-user-static*        fremde CPU-Architekturen in Containern (~179 MB), nur Empfehlung von podman
#   default-fonts-cjk, google-noto-*-cjk-*   chinesische/japanische/koreanische Schriften (~122 MB)
#   NetworkManager-cloud-setup   Einrichtung von Cloud-Servern
# Entschlacken (05.11.2026, je Paket geprüft: nichts Installiertes verlangt es,
# „rpm -e --test“ am Laptop ohne Fehler; Gründe in der Vault-Notiz Systemübersicht):
#   WALinuxAgent-udev, cloud-utils-growpart   Azure bzw. Cloud-VM-Partition vergrößern
#   kdump-utils kexec-tools makedumpfile memstrack dracut-squash squashfs-tools
#                            Speicherabbild bei Kernel-Absturz (kdump war aus)
#   clevis* luksmeta jose libjose dracut-network
#                            LUKS per TPM/Netzwerk entsperren — keine Platte verschlüsselt
#   adcli sssd-*             Anmeldung im Firmennetz (AD, LDAP) — nur lokale Konten
#   lvm2 lvm2-libs device-mapper-persistent-data kpartx   LVM — keine Platte mit LVM
#   stalld criu criu-libs kmscon   Echtzeit-Server, Container einfrieren, andere Textkonsole
#   console-login-helper-messages*   Hinweise in der Textkonsole
#   chunkah                  Abbilder aufteilen — der Bau nutzt das aus fedora-bootc
# Bewusst behalten: socat, nilfs-utils, f2fs-tools, udftools, xfsprogs (Arikushi, 05.11.2026);
# tpm2-tools, weil fedora-bootc das dracut-Modul tpm2-tss verlangt, und das braucht
# „tpm2“ (Bau 0fd577f brach sonst ab)
BASIS_RAUS=(
    python3-boto3 python3-botocore toolbox sos sg3_utils
    ModemManager libqmi libmbim NetworkManager-wwan
    atheros-firmware brcmfmac-firmware tiwilink-firmware nxpwireless-firmware realtek-firmware
    intel-gpu-firmware intel-audio-firmware intel-npu-firmware cirrus-audio-firmware qcom-wwan-firmware
    nvidia-gpu-firmware microcode_ctl "qemu-user-static*" NetworkManager-cloud-setup
    default-fonts-cjk "google-noto-*-cjk-*"
    WALinuxAgent-udev cloud-utils-growpart
    kdump-utils kexec-tools makedumpfile memstrack dracut-squash squashfs-tools
    clevis clevis-dracut clevis-luks clevis-pin-tpm2 clevis-systemd luksmeta jose libjose dracut-network
    adcli sssd-ad sssd-client sssd-common sssd-common-pac sssd-ipa sssd-krb5 sssd-krb5-common sssd-ldap sssd-nfs-idmap
    lvm2 lvm2-libs device-mapper-persistent-data kpartx
    stalld criu criu-libs kmscon
    console-login-helper-messages console-login-helper-messages-issuegen console-login-helper-messages-profile
    chunkah
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
