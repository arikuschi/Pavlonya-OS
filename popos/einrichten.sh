#!/usr/bin/bash
# Pop!_OS — neuen Backup-Dienst einrichten (einmalig, auf dem laufenden Pop!_OS).
#
#   sudo bash einrichten.sh
#
# - installiert popos-backup (Skript + systemd-Zeitplan 0:00)
# - legt /etc/popos-backup/backup.conf an: TrueNAS-Adresse aus /etc/fstab,
#   Kennwort aus ~/.restic-pass
# - nimmt den alten cron-Eintrag (Scripts/restic-backup.sh) heraus
set -euo pipefail

QUELLE="https://raw.githubusercontent.com/arikuschi/Pavlonya-OS/main/popos"
HIER="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2> /dev/null && pwd || echo /nonexistent)"

[[ ${EUID} -eq 0 ]] || { echo "Bitte mit sudo starten."; exit 1; }
BENUTZER="${SUDO_USER:?Bitte mit sudo als normaler Benutzer starten}"
HOMEDIR="$(getent passwd "${BENUTZER}" | cut -d: -f6)"

hole() {  # hole <datei> <ziel> — aus dem Repo-Ordner oder von GitHub
    if [[ -f "${HIER}/$1" ]]; then cp "${HIER}/$1" "$2"; else curl -fsSL "${QUELLE}/$1" -o "$2"; fi
}

echo "== Dienst installieren"
hole popos-backup /usr/local/sbin/popos-backup && chmod 755 /usr/local/sbin/popos-backup
hole popos-backup.service /etc/systemd/system/popos-backup.service
hole popos-backup.timer /etc/systemd/system/popos-backup.timer

echo "== Einstellungen"
mkdir -p /etc/popos-backup && chmod 700 /etc/popos-backup
if [[ ! -e /etc/popos-backup/backup.conf ]]; then
    hole backup.conf.example /etc/popos-backup/backup.conf
    chmod 600 /etc/popos-backup/backup.conf
    NFS="$(awk '$2=="/mnt/truenas-backup" && $3 ~ /^nfs/ {print $1}' /etc/fstab | head -1)"
    if [[ -n "${NFS}" ]]; then
        sed -i "s|^NFS_QUELLE=.*|NFS_QUELLE=\"${NFS}\"|" /etc/popos-backup/backup.conf
    else
        echo "Hinweis: kein NFS-Eintrag für /mnt/truenas-backup in /etc/fstab — NFS_QUELLE von Hand eintragen."
    fi
    sed -i "s|^BENUTZER=.*|BENUTZER=\"${BENUTZER}\"|" /etc/popos-backup/backup.conf
fi
if [[ ! -e /etc/popos-backup/restic-passwort ]]; then
    if [[ -r "${HOMEDIR}/.restic-pass" ]]; then
        install -m600 "${HOMEDIR}/.restic-pass" /etc/popos-backup/restic-passwort
    else
        read -rsp "restic-Kennwort (Bitwarden): " pw < /dev/tty; echo
        printf '%s\n' "${pw}" > /etc/popos-backup/restic-passwort
        chmod 600 /etc/popos-backup/restic-passwort
    fi
fi

echo "== alten cron-Eintrag entfernen"
if crontab -u "${BENUTZER}" -l 2> /dev/null | grep -q "restic-backup.sh"; then
    crontab -u "${BENUTZER}" -l | grep -v "restic-backup.sh" | crontab -u "${BENUTZER}" -
    echo "cron-Eintrag entfernt (Skript selbst bleibt liegen)."
fi

systemctl daemon-reload
systemctl enable popos-backup.timer
echo
echo "Fertig. Ersten Lauf jetzt starten:"
echo "  sudo systemctl start popos-backup && cat /var/lib/popos-backup/status"
