#!/usr/bin/bash
# Pop!_OS — nach einer Neuinstallation alles aus dem Backup zurückholen.
#
#   curl -fsSL https://raw.githubusercontent.com/arikuschi/Pavlonya-OS/main/popos/wiederherstellen.sh | sudo bash
#
# Fragt nach TrueNAS-Adresse (Vault: „Homelab Pavlonya“) und restic-Kennwort
# (Bitwarden). Dann, in dieser Reihenfolge:
#   1. Fremdquellen (Claude, ChatGPT, VS Code, Tabby …)   4. Laufwerke (TrueNAS, Storage Box)
#   2. Programme (Pakete + Flatpaks)                       5. Backup-Dienst
#   3. VPN und WLAN (netplan)                              6. Einstellungen und Daten im Home
# Vorhandene Dateien im System werden nicht überschrieben; das Home wird aus der
# Sicherung zurückgespielt. Enthält keine Geheimnisse — die kommen nur aus dem
# verschlüsselten Backup.
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
    mount -t nfs -o ro,soft,timeo=150,retrans=3 "${NAS}:${NFS_PFAD}" "${MNT}" \
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

SYS=( /etc/netplan /etc/fstab /etc/hosts /root/.ssh /etc/apt/sources.list.d /etc/apt/keyrings
      /usr/share/keyrings /etc/popos-backup /usr/local/sbin/popos-backup
      /etc/systemd/system/popos-backup.service /etc/systemd/system/popos-backup.timer
      /var/lib/popos-backup/inventar )
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

schritt "5. Backup-Dienst"
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

schritt "6. Einstellungen und Daten im Home"
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
