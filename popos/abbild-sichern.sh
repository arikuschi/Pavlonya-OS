#!/usr/bin/bash
# abbild-sichern.sh — komplettes Abbild der Pop!_OS-Platte auf die TrueNAS (30.10.2026).
#
# Rückweg „ohne wenn und aber“ vor der Installation von Pavlonya OS auf diese Platte:
# Partitionstabelle (samt UUIDs), EFI-, Recovery- und Systempartition 1:1. partclone
# liest nur belegte Blöcke, zstd komprimiert. Swap (cryptswap) legt Pop!_OS bei jedem
# Start neu an — er steht nur in der Tabelle. Zurück mit abbild-zurueck.sh.
#
# Läuft unter Pavlonya OS (Samsung-SSD); Pop!_OS darf dabei nicht laufen:
#   curl -fsSLO https://raw.githubusercontent.com/arikuschi/Pavlonya-OS/main/popos/abbild-sichern.sh
#   sudo bash abbild-sichern.sh
# Fragt die TrueNAS-Adresse (Vault: „Homelab Pavlonya“). Die Dateien schreibt der
# Benutzer, nicht root — die NFS-Freigabe hat root_squash (wie bei restic).
set -euo pipefail

NFS_PFAD="/mnt/pavlonya-data/backups/linux"
MNT=/var/mnt/popos-abbild
WERKZEUG=localhost/pavlonya-abbild-werkzeug

[[ ${EUID} -eq 0 ]] || { echo "Bitte mit sudo starten:  sudo bash abbild-sichern.sh"; exit 1; }
BENUTZER="${SUDO_USER:-}"
[[ -n "${BENUTZER}" && "${BENUTZER}" != root ]] || read -rp "Benutzer, dem die Dateien gehören (z. B. arikushi): " BENUTZER
GID="$(id -g "${BENUTZER}")"
als_benutzer() { setpriv --reuid="${BENUTZER}" --regid="${GID}" --init-groups "$@"; }

# partclone fehlt im Image — einmalig in einem Fedora-Container holen
werkzeug() {
    podman image exists "${WERKZEUG}" && return
    echo "Werkzeug (partclone, zstd) einmalig holen …"
    podman rm -f pavlonya-abbild-bau > /dev/null 2>&1 || true
    podman run --name pavlonya-abbild-bau quay.io/fedora/fedora:44 dnf -y -q install partclone zstd > /dev/null
    podman commit -q pavlonya-abbild-bau "${WERKZEUG}" > /dev/null
    podman rm pavlonya-abbild-bau > /dev/null
}
im_werkzeug() { podman run --rm -i --privileged --security-opt label=disable -v /dev:/dev "${WERKZEUG}" "$@"; }
partnr() { cat "/sys/class/block/$(basename "$1")/partition"; }

# --- Pop!_OS-Platte finden: die Platte mit einem ext4, dessen os-release ID=pop sagt
PLATTE=""
for d in $(lsblk -dnpo NAME,TYPE | awk '$2 == "disk" {print $1}'); do
    for p in $(lsblk -nlpo NAME,FSTYPE "${d}" | awk '$2 == "ext4" {print $1}'); do
        t="$(mktemp -d)"
        if mount -o ro,noload "${p}" "${t}" 2> /dev/null; then
            grep -qs '^ID=pop' "${t}/etc/os-release" && PLATTE="${d}"
            umount "${t}"
        fi
        rmdir "${t}"
    done
done
[[ -n "${PLATTE}" ]] || { echo "Keine Platte mit Pop!_OS gefunden."; exit 1; }
if lsblk -nlo MOUNTPOINTS "${PLATTE}" | grep -q .; then
    echo "Auf ${PLATTE} ist etwas eingehängt — läuft Pop!_OS? Erst aushängen."; exit 1
fi
echo "=== Pop!_OS-Platte: ${PLATTE} — $(lsblk -dno MODEL,SIZE "${PLATTE}" | xargs)"
lsblk -o NAME,SIZE,FSTYPE,LABEL "${PLATTE}"

read -rp "TrueNAS-Adresse (IP, steht im Vault unter „Homelab Pavlonya“): " NAS
mkdir -p "${MNT}"
EINGEHAENGT=0
mountpoint -q "${MNT}" || { mount -t nfs -o soft,timeo=150,retrans=3 "${NAS}:${NFS_PFAD}" "${MNT}"; EINGEHAENGT=1; }
trap '[[ ${EINGEHAENGT} == 1 ]] && umount "${MNT}"' EXIT

ZIEL="${MNT}/popos-abbild-$(date +%Y-%m-%d_%H%M)"
als_benutzer mkdir "${ZIEL}"
FREI=$(( $(stat -f -c '%a*%S' "${MNT}") ))
GROESSE=$(lsblk -bdno SIZE "${PLATTE}")
(( FREI > GROESSE )) || { echo "Zu wenig Platz auf der TrueNAS ($((FREI / 10**9)) GB frei)."; exit 1; }
echo "Ziel: ${ZIEL} ($((FREI / 10**9)) GB frei)"

werkzeug

# --- Beschreibung der Platte: zum Zurückschreiben und zum Wiedererkennen
sfdisk -d "${PLATTE}" | als_benutzer tee "${ZIEL}/tabelle.sfdisk" > /dev/null
{
    echo "datum=$(date -Iseconds)"
    echo "modell=$(lsblk -dno MODEL "${PLATTE}" | xargs)"
    echo "seriennummer=$(lsblk -dno SERIAL "${PLATTE}" | xargs)"
    echo "groesse=${GROESSE}"
    echo
    lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,UUID,PARTUUID "${PLATTE}"
    echo
    blkid "${PLATTE}"* || true
} | als_benutzer tee "${ZIEL}/info.txt" > /dev/null
efibootmgr -v 2> /dev/null | als_benutzer tee "${ZIEL}/efiboot.txt" > /dev/null || true

# --- Partitionen sichern
: | als_benutzer tee "${ZIEL}/partitionen.txt" > /dev/null
for p in $(lsblk -nlpo NAME,TYPE "${PLATTE}" | awk '$2 == "part" {print $1}'); do
    nr="$(partnr "${p}")"
    fs="$(lsblk -no FSTYPE "${p}" | xargs)"
    case "${fs}" in
        ext4|vfat) werkzeug_fs="${fs}" ;;
        ""|swap)   echo "Partition ${nr} (${fs:-ohne Dateisystem, cryptswap}): nur in der Tabelle"
                   echo "${nr} leer -" | als_benutzer tee -a "${ZIEL}/partitionen.txt" > /dev/null
                   continue ;;
        *)         werkzeug_fs="dd" ;;
    esac
    datei="p${nr}.${werkzeug_fs}.pcl.zst"
    echo "--- Partition ${nr} (${fs}, $(lsblk -no SIZE "${p}" | xargs)) → ${datei}"
    im_werkzeug bash -o pipefail -c "partclone.${werkzeug_fs} -c -s ${p} -o - -L /dev/null | zstd -T0 -6 -q" \
        | als_benutzer dd of="${ZIEL}/${datei}" bs=4M status=none
    echo "${nr} ${werkzeug_fs} ${datei}" | als_benutzer tee -a "${ZIEL}/partitionen.txt" > /dev/null
done

# --- Prüfen: jedes Abbild vollständig lesen und gegen seine Prüfsummen testen
echo "=== Prüfen …"
while read -r nr fs datei; do
    [[ "${fs}" == leer ]] && continue
    als_benutzer cat "${ZIEL}/${datei}" \
        | im_werkzeug bash -o pipefail -c "zstd -dc | partclone.chkimg -s - -L /dev/null" > /dev/null 2>&1 \
        || { echo "FEHLER: ${datei} ist nicht in Ordnung — Abbild NICHT verwenden."; exit 1; }
    echo "ok: ${datei}"
done < "${ZIEL}/partitionen.txt"
als_benutzer bash -c "cd '${ZIEL}' && sha256sum *.zst tabelle.sfdisk partitionen.txt > SHA256SUMS"

echo
echo "=== Fertig: ${ZIEL}"
als_benutzer du -sh "${ZIEL}"
echo "Zurück, falls nötig (unter Pavlonya OS von der Samsung-SSD):"
echo "  curl -fsSLO https://raw.githubusercontent.com/arikuschi/Pavlonya-OS/main/popos/abbild-zurueck.sh"
echo "  sudo bash abbild-zurueck.sh"
