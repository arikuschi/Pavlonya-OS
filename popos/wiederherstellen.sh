#!/usr/bin/bash
# Pop!_OS — nach einer Neuinstallation alles aus dem Backup zurückholen.
#
#   curl -fsSL https://raw.githubusercontent.com/arikuschi/Pavlonya-OS/main/popos/wiederherstellen.sh | sudo bash
#
# Fragt nach TrueNAS-Adresse (Vault: „Homelab Pavlonya“) und restic-Kennwort
# (Bitwarden). Dann, in dieser Reihenfolge:
#   1. Fremdquellen (Claude, ChatGPT, VS Code, Tabby …)   5. System-Einstellungen (Grafik,
#   2. Programme (Pakete, Flatpaks, rclone)                  Drucker, SSH, Bluetooth, FUSE)
#   3. VPN und WLAN (netplan)                              6. Backup-Dienst
#   4. Laufwerke (TrueNAS, Storage Box)                    7. Home: Einstellungen und Daten
# Vorhandene Dateien im System werden nicht überschrieben — außer in Schritt 5, wo die
# Vorgaben der Neuinstallation bewusst durch den gesicherten Stand ersetzt werden (die
# frische Fassung bleibt als *.neuinstallation daneben). Das Home wird aus der Sicherung
# zurückgespielt. Enthält keine Geheimnisse — die kommen nur aus dem verschlüsselten Backup.
set -uo pipefail

NFS_PFAD="/mnt/pavlonya-data/backups/linux"
REPO_UNTERORDNER="restic"
HOST="pop-os"
MNT=/mnt/popos-wiederherstellen
LOG=/var/log/popos-wiederherstellen.log

frage()  { local a; read -rp "$1" a < /dev/tty; echo "${a}"; }
schritt() { echo; echo "=== $* ==="; }

[[ ${EUID} -eq 0 ]] || { echo "Bitte mit sudo starten."; exit 1; }
exec > >(tee -a "${LOG}") 2>&1

BENUTZER="${SUDO_USER:-}"
[[ -n "${BENUTZER}" && "${BENUTZER}" != root ]] || BENUTZER="$(frage "Benutzer (z. B. arikushi): ")"
HOMEDIR="$(getent passwd "${BENUTZER}" | cut -d: -f6)"
GID="$(id -g "${BENUTZER}" 2> /dev/null)"
[[ -n "${HOMEDIR}" && -n "${GID}" ]] || { echo "Benutzer ${BENUTZER} gibt es nicht."; exit 1; }

echo "Pop!_OS — Wiederherstellung für ${BENUTZER} ($(date '+%d.%m.%Y %H:%M'), Protokoll: ${LOG})"
# Vorgaben per Umgebung nur für automatisierte Tests (POPOS_NAS, POPOS_PASSWORT, POPOS_DATEN)
NAS="${POPOS_NAS:-$(frage "TrueNAS-Adresse (IP): ")}"
if [[ -n "${POPOS_PASSWORT:-}" ]]; then PASSWORT="${POPOS_PASSWORT}"; else
    read -rsp "restic-Kennwort (Bitwarden): " PASSWORT < /dev/tty; echo; fi
DATEN="${POPOS_DATEN:-$(frage "Auch alle Daten im Home zurückholen (Dokumente, Bilder …, ca. 1–2 Std.)? [J/n] ")}"

ARBEIT="$(mktemp -d /var/tmp/popos-wiederherstellen.XXXX)"
chown "${BENUTZER}:${GID}" "${ARBEIT}"; chmod 700 "${ARBEIT}"
printf '%s\n' "${PASSWORT}" > "${ARBEIT}/pw"; chown "${BENUTZER}" "${ARBEIT}/pw"; chmod 600 "${ARBEIT}/pw"
EINGEHAENGT=0
aufraeumen() { [[ ${EINGEHAENGT} == 1 ]] && umount "${MNT}"; rm -rf "${ARBEIT}"; }
trap aufraeumen EXIT

als_benutzer() {
    setpriv --reuid="${BENUTZER}" --regid="${GID}" --init-groups \
        env HOME="${HOMEDIR}" RESTIC_CACHE_DIR="${HOMEDIR}/.cache/restic" \
        RESTIC_REPOSITORY="${MNT}/${REPO_UNTERORDNER}" RESTIC_PASSWORD_FILE="${ARBEIT}/pw" "$@"
}
FEHLER=()

schritt "0. Werkzeuge und TrueNAS"
apt-get update -qq
apt-get install -y -qq restic nfs-common curl > /dev/null || { echo "restic/nfs-common nicht installierbar"; exit 1; }
mkdir -p "${MNT}"
if ! mountpoint -q "${MNT}"; then
    # nicht schreibgeschützt: restic legt auch beim Lesen eine Sperrdatei an
    # (Laptop 14.10.2026: „read-only file system“ bei locks/)
    mount -t nfs -o soft,timeo=150,retrans=3 "${NAS}:${NFS_PFAD}" "${MNT}" \
        || { echo "TrueNAS ${NAS} nicht erreichbar — im Heimnetz?"; exit 1; }
    EINGEHAENGT=1
fi
if ! als_benutzer restic cat config > "${ARBEIT}/check.log" 2>&1; then
    echo "Repository nicht lesbar. Meldung von restic:"
    grep -v '^\s*$' "${ARBEIT}/check.log" | tail -3 | sed 's/^/   /'
    echo "(„wrong password“ = Kennwort falsch; „permission denied“ = Zugriffsrecht auf der TrueNAS)"
    exit 1
fi
SNAP="$(als_benutzer restic snapshots --host "${HOST}" --latest 1 --compact 2> /dev/null | awk '/^[0-9a-f]{8} /{print $1" vom "$2" "$3}' | tail -1)"
[[ -n "${SNAP}" ]] || { echo "Keine Sicherung von ${HOST} gefunden."; exit 1; }
echo "Letzte Sicherung: ${SNAP}"

SYS=( /etc/netplan /etc/NetworkManager /var/lib/systemd/linger
      /etc/fstab /etc/hosts /root/.ssh /etc/apt/sources.list.d /etc/apt/keyrings
      /usr/share/keyrings /etc/popos-backup /usr/local/sbin/popos-backup
      /etc/systemd/system/popos-backup.service /etc/systemd/system/popos-backup.timer
      /var/lib/popos-backup/inventar
      /etc/modprobe.d /etc/fuse.conf /etc/cups/printers.conf /etc/cups/ppd /etc/ssh /var/lib/bluetooth )
INCL=(); for p in "${SYS[@]}"; do INCL+=(--include "${p}"); done
# restic läuft als Repo-Besitzer; die Dateien landen erst im Arbeitsordner und werden
# dann von root an ihren Platz gelegt
als_benutzer restic restore latest --host "${HOST}" --target "${ARBEIT}/s" "${INCL[@]}" > "${ARBEIT}/restore.log" 2>&1 \
    || { echo "Systemteil nicht wiederherstellbar:"; tail -5 "${ARBEIT}/restore.log"; exit 1; }
S="${ARBEIT}/s"

kopiere_fehlende() {  # kopiere_fehlende <quellordner> <zielordner> <modus> <besitzer>
    local q="$1" z="$2" n=0 f
    [[ -d "${q}" ]] || { echo 0; return; }
    mkdir -p "${z}"
    for f in "${q}"/*; do
        [[ -f "${f}" ]] || continue
        [[ -e "${z}/$(basename "${f}")" ]] && continue
        install -m "$3" -o "$4" -g "$4" "${f}" "${z}/$(basename "${f}")" && n=$((n + 1))
    done
    echo "${n}"
}

schritt "1. Fremdquellen"
echo "Paketquellen: $(kopiere_fehlende "${S}/etc/apt/sources.list.d" /etc/apt/sources.list.d 644 root) neu"
echo "Schlüssel:    $(( $(kopiere_fehlende "${S}/etc/apt/keyrings" /etc/apt/keyrings 644 root) + $(kopiere_fehlende "${S}/usr/share/keyrings" /usr/share/keyrings 644 root) )) neu"
apt-get update -qq || FEHLER+=("apt-get update meldete Fehler")

schritt "2. Programme"
INV="${S}/var/lib/popos-backup/inventar"
if [[ -s "${INV}/apt-pakete.txt" ]]; then
    while read -r paket; do
        [[ -n "${paket}" ]] || continue
        if dpkg -s "${paket}" > /dev/null 2>&1; then continue; fi
        echo "Installiere ${paket}"
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${paket}" > /dev/null 2>&1 \
            || FEHLER+=("Paket ${paket} nicht installierbar")
    done < "${INV}/apt-pakete.txt"
fi
declare -A FLATREPO=( [flathub]="https://dl.flathub.org/repo/flathub.flatpakrepo"
                      [cosmic]="https://apt.pop-os.org/cosmic/cosmic.flatpakrepo" )
if command -v flatpak > /dev/null && [[ -s "${INV}/flatpak-apps.txt" ]]; then
    for r in $(awk '{print $2}' "${INV}/flatpak-apps.txt" | sort -u); do
        [[ -n "${FLATREPO[$r]:-}" ]] || { FEHLER+=("Flatpak-Quelle ${r} unbekannt"); continue; }
        runuser -u "${BENUTZER}" -- env HOME="${HOMEDIR}" \
            flatpak remote-add --user --if-not-exists "${r}" "${FLATREPO[$r]}" || FEHLER+=("Flatpak-Quelle ${r}")
    done
    while read -r app origin; do
        [[ -n "${app}" ]] || continue
        echo "Flatpak ${app}"
        runuser -u "${BENUTZER}" -- env HOME="${HOMEDIR}" \
            flatpak install --user -y --noninteractive "${origin}" "${app}" > /dev/null 2>&1 \
            || FEHLER+=("Flatpak ${app}")
    done < "${INV}/flatpak-apps.txt"
fi
if grep -qx "claude-code" "${INV}/sonstiges.txt" 2> /dev/null && [[ ! -x "${HOMEDIR}/.local/bin/claude" ]]; then
    echo "Claude Code"
    runuser -u "${BENUTZER}" -- env HOME="${HOMEDIR}" bash -c 'curl -fsSL https://claude.ai/install.sh | bash' > /dev/null 2>&1 \
        || FEHLER+=("Claude Code")
fi

if grep -qx "rclone" "${INV}/sonstiges.txt" 2> /dev/null && ! command -v rclone > /dev/null; then
    echo "rclone"   # unter Pop!_OS ohne Paket installiert; hier aus Ubuntus Paketquelle
    apt-get install -y -qq rclone > /dev/null 2>&1 || FEHLER+=("rclone")
fi

schritt "3. VPN und WLAN"
echo "netplan-Dateien: $(kopiere_fehlende "${S}/etc/netplan" /etc/netplan 600 root) neu"
echo "NetworkManager:  $(kopiere_fehlende "${S}/etc/NetworkManager/system-connections" /etc/NetworkManager/system-connections 600 root) neu"

schritt "4. Laufwerke (TrueNAS, Storage Box)"
mkdir -p /root/.ssh && chmod 700 /root/.ssh
echo "Schlüssel root: $(kopiere_fehlende "${S}/root/.ssh" /root/.ssh 600 root) neu"
if [[ -f "${S}/etc/fstab" ]]; then
    while read -r quelle ziel typ rest; do
        [[ "${quelle}" =~ ^# || -z "${quelle}" ]] && continue
        [[ "${typ}" =~ ^(nfs|nfs4|cifs|fuse\.sshfs)$ ]] || continue
        if awk -v z="${ziel}" '$2==z {f=1} END {exit !f}' /etc/fstab; then continue; fi
        echo "${quelle} ${ziel} ${typ} ${rest}" >> /etc/fstab
        mkdir -p "${ziel}"
        echo "fstab: ${ziel} (${typ})"
    done < "${S}/etc/fstab"
    command -v sshfs > /dev/null || apt-get install -y -qq sshfs > /dev/null
fi
if [[ -f "${S}/etc/hosts" ]]; then
    grep -vE '^\s*(#|$)' "${S}/etc/hosts" | while read -r zeile; do
        grep -qxF "${zeile}" /etc/hosts || { echo "${zeile}" >> /etc/hosts; echo "hosts: ${zeile}"; }
    done
fi

schritt "5. System-Einstellungen (Grafik, Drucker, SSH, Bluetooth, FUSE)"
ersetze() {  # ersetze <pfad ohne / vorn> <modus> <gruppe> — gesicherten Stand an die Stelle legen
    local q="${S}/$1" z="/$1"
    [[ -f "${q}" ]] || return 1
    if [[ -e "${z}" ]]; then
        cmp -s "${q}" "${z}" && return 0
        cp -a "${z}" "${z}.neuinstallation"
    fi
    install -D -m "$2" -o root -g "$3" "${q}" "${z}"
}
# Grafik: amdgpu vor nvidia laden (sonst schwarzer Start mit HDMI-Monitor), Grafikmodus
n="$(kopiere_fehlende "${S}/etc/modprobe.d" /etc/modprobe.d 644 root)"
echo "Modul-Regeln: ${n} neu"
if (( n > 0 )) && command -v update-initramfs > /dev/null; then
    update-initramfs -u -k all > /dev/null 2>&1 || FEHLER+=("update-initramfs")
fi
MODUS="$(tr -d '[:space:]' < "${INV}/grafik.txt" 2> /dev/null)"
if [[ "${MODUS}" =~ ^(nvidia|hybrid|integrated|compute)$ ]] && command -v system76-power > /dev/null; then
    if [[ "$(system76-power graphics 2> /dev/null)" != "${MODUS}" ]]; then
        system76-power graphics "${MODUS}" > /dev/null 2>&1 && echo "Grafikmodus: ${MODUS} (wirkt nach dem Neustart)" \
            || FEHLER+=("Grafikmodus ${MODUS}")
    else
        echo "Grafikmodus: ${MODUS}"
    fi
fi
# FUSE: user_allow_other
ersetze etc/fuse.conf 644 root && echo "fuse.conf"
# Drucker
if [[ -f "${S}/etc/cups/printers.conf" ]] && [[ -d /etc/cups ]]; then
    command -v systemctl > /dev/null && systemctl stop cups 2> /dev/null
    ersetze etc/cups/printers.conf 600 lp
    for f in "${S}"/etc/cups/ppd/*.ppd; do
        [[ -f "${f}" ]] && install -D -m 640 -o root -g lp "${f}" "/etc/cups/ppd/$(basename "${f}")"
    done
    command -v systemctl > /dev/null && { systemctl start cups 2> /dev/null || FEHLER+=("CUPS startet nicht"); }
    echo "Drucker: $(grep -c '^<Printer\|^<DefaultPrinter' /etc/cups/printers.conf) eingerichtet"
fi
# SSH-Server: Einstellungen und Host-Schlüssel (Gegenstellen sehen denselben Rechner)
if [[ -f "${S}/etc/ssh/sshd_config" ]] && [[ -d /etc/ssh ]]; then
    ersetze etc/ssh/sshd_config 644 root
    for f in "${S}"/etc/ssh/sshd_config.d/*.conf; do
        [[ -f "${f}" ]] && ersetze "etc/ssh/sshd_config.d/$(basename "${f}")" 644 root
    done
    for f in "${S}"/etc/ssh/ssh_host_*_key; do
        [[ -f "${f}" ]] || continue
        ersetze "etc/ssh/$(basename "${f}")" 600 root
        ersetze "etc/ssh/$(basename "${f}").pub" 644 root
    done
    command -v systemctl > /dev/null && systemctl try-restart ssh.service 2> /dev/null
    echo "SSH-Server: Einstellungen und Host-Schlüssel"
fi
# Bluetooth: gekoppelte Geräte (je Adapter; was die Neuinstallation schon kennt, bleibt)
if [[ -d "${S}/var/lib/bluetooth" ]]; then
    command -v systemctl > /dev/null && systemctl stop bluetooth 2> /dev/null
    n=0
    for adapter in "${S}"/var/lib/bluetooth/*/; do
        a="/var/lib/bluetooth/$(basename "${adapter}")"
        mkdir -p "${a}"
        for geraet in "${adapter}"*; do
            [[ -e "${geraet}" && ! -e "${a}/$(basename "${geraet}")" ]] || continue
            cp -r "${geraet}" "${a}/" && n=$((n + 1))
        done
    done
    chown -R root:root /var/lib/bluetooth
    find /var/lib/bluetooth -type d -exec chmod 700 {} + ; find /var/lib/bluetooth -type f -exec chmod 600 {} +
    command -v systemctl > /dev/null && systemctl start bluetooth 2> /dev/null
    echo "Bluetooth: ${n} Einträge"
fi

# Benutzer-Timer auch ohne Anmeldung (z. B. Forgejo-Dump abholen): loginctl enable-linger
for f in "${S}"/var/lib/systemd/linger/*; do
    [[ -e "${f}" ]] || continue
    loginctl enable-linger "$(basename "${f}")" 2> /dev/null && echo "Linger: $(basename "${f}")" \
        || FEHLER+=("loginctl enable-linger $(basename "${f}")")
done

schritt "6. Backup-Dienst"
mkdir -p /etc/popos-backup && chmod 700 /etc/popos-backup
kopiere_fehlende "${S}/etc/popos-backup" /etc/popos-backup 600 root > /dev/null
[[ -e /etc/popos-backup/restic-passwort ]] || install -m600 "${ARBEIT}/pw" /etc/popos-backup/restic-passwort
[[ -e /usr/local/sbin/popos-backup ]] || install -m755 "${S}/usr/local/sbin/popos-backup" /usr/local/sbin/popos-backup
for u in popos-backup.service popos-backup.timer; do
    [[ -e "/etc/systemd/system/${u}" ]] || install -m644 "${S}/etc/systemd/system/${u}" "/etc/systemd/system/${u}"
done
if command -v systemctl > /dev/null; then
    systemctl daemon-reload && systemctl enable popos-backup.timer || FEHLER+=("Backup-Zeitplan nicht aktiviert")
fi

schritt "7. Einstellungen und Daten im Home"
if [[ "${DATEN,,}" == n* ]]; then
    echo "Übersprungen (später: dieses Skript erneut starten)."
else
    # restic als Benutzer: Dateien gehören danach automatisch ihm. „latest:<home>“
    # stellt nur den Inhalt des Home-Ordners her, ohne /home selbst anzufassen.
    als_benutzer restic restore "latest:${HOMEDIR}" --host "${HOST}" --target "${HOMEDIR}" \
        || FEHLER+=("Home nicht vollständig zurückgeholt — Protokoll ${LOG}")
fi

schritt "Abschluss"
command -v netplan > /dev/null && { netplan apply || FEHLER+=("netplan apply"); }
mount -a 2> /dev/null || FEHLER+=("Nicht alle Laufwerke eingehängt (mount -a)")
if (( ${#FEHLER[@]} )); then
    echo "Fertig mit Hinweisen:"; printf ' - %s\n' "${FEHLER[@]}"
else
    echo "Fertig, ohne Fehler."
fi
echo "Bitte neu starten. Protokoll: ${LOG}"
