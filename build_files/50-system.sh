#!/usr/bin/bash
# 50-system.sh — eigene Dateien einspielen, Dienste aktivieren.
set -euxo pipefail

cp -a /system_files/. /

# Image-Name für die einmalige Umstellung auf das signierte Image
echo "${IMAGE_REF}:${FEDORA_VERSION}" > /usr/share/pavlonya-os/image-ref

# --- Signaturprüfung für eigene Updates --------------------------------------
# Ohne öffentlichen Schlüssel bleibt die Prüfung aus (lokaler Testbau).
if [[ -s /keys/cosign.pub ]]; then
    install -Dm644 /keys/cosign.pub /etc/pki/containers/pavlonya-os.pub
    sed "s|@IMAGE_REF@|${IMAGE_REF}|" /usr/share/pavlonya-os/policy.json.in \
        > /etc/containers/policy.json
else
    echo "HINWEIS: keys/cosign.pub fehlt — Image ohne Signaturprüfung gebaut."
fi

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
    pavlonya-signiert-umstellen.service

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
test -f /usr/share/wayland-sessions/cosmic.desktop
# COSMIC-Vorgabe für die Tastatur: gilt für jeden Benutzer ohne eigene Einstellung
# und damit auch für den Anmeldebildschirm (der liest die Einstellung des Benutzers)
grep -q 'layout: "de"' /usr/share/cosmic/com.system76.CosmicComp/v1/xkb_config
GREETER_USER="$(sed -nE 's/^\s*user\s*=\s*"([^"]+)".*/\1/p' /etc/greetd/cosmic-greeter.toml | head -1)"
getent passwd "${GREETER_USER}" > /dev/null || {
    echo "FEHLER: Greeter-Benutzer '${GREETER_USER}' existiert nicht" >&2; exit 1; }
