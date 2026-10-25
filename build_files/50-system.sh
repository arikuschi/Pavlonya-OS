#!/usr/bin/bash
# 50-system.sh — eigene Dateien einspielen, Dienste aktivieren.
set -euxo pipefail

cp -a /system_files/. /

# Image-Name; für ihn verlangt /etc/containers/policy.json die cosign-Signatur
echo "${IMAGE_REF}:${FEDORA_VERSION}" > /usr/share/pavlonya-os/image-ref

# --- Name und Logo -----------------------------------------------------------
# Angezeigt wird überall „Pavlonya OS“: Startmenü (ostree nimmt PRETTY_NAME als
# Titel der Einträge), Terminal-Anzeigen, COSMIC „Über“. ID=fedora und
# VERSION_ID bleiben — daran erkennen bootc, dnf, Distrobox und der Installer
# das System. DEFAULT_HOSTNAME gilt nur, solange kein Rechnername gesetzt ist.
# Eine Datei statt Symlink: sed -i schreibt /usr/lib/os-release als eigene Datei.
setze_os_release() {
    local schluessel="$1" wert="$2"
    if grep -q "^${schluessel}=" /usr/lib/os-release; then
        sed -i "s|^${schluessel}=.*|${schluessel}=${wert}|" /usr/lib/os-release
    else
        echo "${schluessel}=${wert}" >> /usr/lib/os-release
    fi
}
setze_os_release NAME             '"Pavlonya OS"'
setze_os_release PRETTY_NAME      "\"Pavlonya OS ${FEDORA_VERSION} (COSMIC)\""
setze_os_release LOGO             pavlonya-os
setze_os_release DEFAULT_HOSTNAME '"pavlonya-os"'
setze_os_release HOME_URL         '"https://github.com/arikuschi/Pavlonya-OS"'
install -Dm644 /usr/share/icons/hicolor/scalable/apps/pavlonya-os.svg \
               /usr/share/pixmaps/pavlonya-os.svg
if command -v gtk-update-icon-cache > /dev/null; then
    gtk-update-icon-cache -q -f -t /usr/share/icons/hicolor
fi
cat /usr/lib/os-release

# --- Startbild (Plymouth) -----------------------------------------------------
# Logo mit Schriftzug und Fortschrittsbalken (Wunsch 24.10.2026). Die Bilder rendert
# die Baustufe „startbild“; die Design-Datei (two-step) liegt in system_files. Muss vor
# 60-initramfs.sh stehen: dracut nimmt das eingestellte Design in die initramfs auf.
# Angezeigt wird es mit den Kernel-Parametern aus /usr/lib/bootc/kargs.d.
install -m644 /tmp/startbild/*.png /usr/share/plymouth/themes/pavlonya/
plymouth-set-default-theme pavlonya
test "$(plymouth-set-default-theme)" = pavlonya

# --- Firmware-Startmenü (F12) ----------------------------------------------------
# Die Acer-Firmware (Insyde) kennt \EFI\fedora\shim.efi und legt dafür bei jedem
# Start selbst einen Eintrag „Fedora“ an, sogar an erster Stelle — auch wenn er
# gelöscht wurde (25.10.2026, erkennbar an der Kennung „RC“ im Eintrag). shim.efi
# ist nur eine Kopie von shimx64.efi, den der Eintrag „Pavlonya OS“ nutzt; ohne sie
# legt bootupd sie bei Updates nicht wieder auf die EFI-Partition.
# BOOTX64.CSV benennt den Eintrag, den shim auf dem Notweg (\EFI\BOOT) anlegt.
for v in /usr/lib/efi/shim/*/EFI/fedora; do
    rm -f "${v}/shim.efi"
    iconv -f UTF-16LE -t UTF-8 "${v}/BOOTX64.CSV" \
        | sed 's/,Fedora,,This is the boot entry for Fedora/,Pavlonya OS,,This is the boot entry for Pavlonya OS/' \
        | iconv -f UTF-8 -t UTF-16LE > "${v}/BOOTX64.CSV.neu"
    mv "${v}/BOOTX64.CSV.neu" "${v}/BOOTX64.CSV"
    iconv -f UTF-16LE -t UTF-8 "${v}/BOOTX64.CSV"
    iconv -f UTF-16LE -t UTF-8 "${v}/BOOTX64.CSV" | grep -q ',Pavlonya OS,'
    test -s "${v}/shimx64.efi" && test ! -e "${v}/shim.efi"
done

# --- Signaturprüfung für eigene Updates --------------------------------------
# Ohne öffentlichen Schlüssel bleibt die Prüfung aus (lokaler Testbau).
# policy.json: Grundregel „annehmen“ (Distrobox, Podman), für das eigene Image
# sigstoreSigned. bootc wendet die Regel bei jedem Update an, auch ohne
# --enforce-container-sigpolicy; dieser Schalter verweigert sich sogar, solange
# die Grundregel „annehmen“ lautet (am Laptop 21.10.2026 gesehen).
if [[ -s /keys/cosign.pub ]]; then
    install -Dm644 /keys/cosign.pub /etc/pki/containers/pavlonya-os.pub
    sed "s|@IMAGE_REF@|${IMAGE_REF}|" /usr/share/pavlonya-os/policy.json.in \
        > /etc/containers/policy.json
else
    echo "HINWEIS: keys/cosign.pub fehlt — Image ohne Signaturprüfung gebaut."
fi

# --- .local-Namen (mDNS) -----------------------------------------------------
# nss-mdns allein reicht nicht: „mdns4_minimal“ muss in der hosts-Zeile von
# /etc/nsswitch.conf stehen. Mit authselect über dessen Schalter, sonst direkt.
if ! grep -Eq '^hosts:.*mdns4_minimal' /etc/nsswitch.conf; then
    if authselect current > /dev/null 2>&1; then
        authselect enable-feature with-mdns4
    else
        sed -i --follow-symlinks -E \
            '/^hosts:/{/mdns4_minimal/!s/^(hosts:[[:space:]]+files)/\1 mdns4_minimal [NOTFOUND=return]/}' \
            /etc/nsswitch.conf
    fi
fi
grep -E '^hosts:' /etc/nsswitch.conf
grep -Eq '^hosts:.*mdns4_minimal' /etc/nsswitch.conf

# --- Dienste -----------------------------------------------------------------
systemctl enable \
    cosmic-greeter.service \
    NetworkManager.service \
    bluetooth.service \
    firewalld.service \
    sshd.service \
    power-profiles-daemon.service \
    switcheroo-control.service \
    fstrim.timer \
    pavlonya-update.timer \
    pavlonya-flatpaks.service \
    pavlonya-ensure-user.service \
    pavlonya-backup.timer

# Für jeden Benutzer: Distroboxen täglich aktualisieren (läuft nach der Anmeldung)
systemctl --global enable pavlonya-distrobox-upgrade.timer

# NVIDIA: VRAM über Standby und Ruhezustand retten
# Welche Units es gibt, hängt von der Treiberversion bzw. Paketierung ab —
# nur aktivieren, was vorhanden ist, und im Log festhalten.
echo "### NVIDIA-Units im Image:"
ls /usr/lib/systemd/system | grep -i nvidia || echo "(keine)"
for unit in nvidia-suspend.service nvidia-resume.service nvidia-hibernate.service \
            nvidia-suspend-then-hibernate.service nvidia-powerd.service; do
    if [[ -f "/usr/lib/systemd/system/${unit}" ]]; then
        systemctl enable "${unit}"
    else
        echo "HINWEIS: ${unit} gibt es nicht"
    fi
done

# Automatische Updates mit Neustart aus — Updates werden nur bereitgelegt
# (pavlonya-update.timer) und beim nächsten Neustart aktiv.
systemctl disable bootc-fetch-apply-updates.timer 2>/dev/null || true

# fedora-bootc ist ein Server-Image: ohne das startet kein Login-Bildschirm
systemctl set-default graphical.target
if [[ ! -L /etc/systemd/system/display-manager.service ]]; then
    ln -sf /usr/lib/systemd/system/cosmic-greeter.service \
           /etc/systemd/system/display-manager.service
fi

# --- Selbstprüfung -----------------------------------------------------------
test "$(systemctl get-default)" = graphical.target
grep -q '^NAME="Pavlonya OS"$' /etc/os-release
grep -q '^ID=fedora$' /etc/os-release
grep -q '^VERSION_ID=' /etc/os-release
test -f /usr/share/pixmaps/pavlonya-os.svg
for f in pavlonya.plymouth watermark.png entry.png bullet.png lock.png; do
    test -s "/usr/share/plymouth/themes/pavlonya/${f}"
done
grep -q '"rhgb"' /usr/lib/bootc/kargs.d/10-pavlonya-startbild.toml
test -f /usr/share/wayland-sessions/cosmic.desktop
# COSMIC-Vorgabe für die Tastatur: gilt für jeden Benutzer ohne eigene Einstellung
# und damit auch für den Anmeldebildschirm (der liest die Einstellung des Benutzers)
grep -q 'layout: "de"' /usr/share/cosmic/com.system76.CosmicComp/v1/xkb_config
# Nummernblock bei jedem Start an — Anmeldebildschirm und Sitzung (Wunsch
# 21.10.2026). Systemvorgabe von cosmic-comp; wer in den Einstellungen etwas
# anderes wählt, behält seine eigene Einstellung.
grep -q 'numlock_state: BootOn' /usr/share/cosmic/com.system76.CosmicComp/v1/keyboard_config
# Dock: Vorgabe wie das Pop!_OS-Dock (12.10.2026) statt Fedoras Liste mit
# Firefox, das hier nicht installiert ist. Gilt für Benutzer ohne eigene Dock-Einstellung.
grep -q 'one.ablaze.floorp' /usr/share/cosmic/com.system76.CosmicAppList/v1/favorites
GREETER_USER="$(sed -nE 's/^\s*user\s*=\s*"([^"]+)".*/\1/p' /etc/greetd/cosmic-greeter.toml | head -1)"
getent passwd "${GREETER_USER}" > /dev/null || {
    echo "FEHLER: Greeter-Benutzer '${GREETER_USER}' existiert nicht" >&2; exit 1; }
