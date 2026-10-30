#!/usr/bin/bash
# abbild-zurueck.sh — Pop!_OS-Abbild von der TrueNAS auf die Platte zurückschreiben
# (30.10.2026). Gegenstück zu abbild-sichern.sh: Partitionstabelle samt UUIDs, dann
# jede Partition; danach ist Pop!_OS exakt im gesicherten Stand. Die Zielplatte wird
# KOMPLETT überschrieben — was darauf liegt (z. B. Pavlonya OS), ist danach weg.
#
# Läuft unter einem anderen System als der Zielplatte, z. B. Pavlonya OS auf der
# Samsung-SSD:
#   curl -fsSLO https://raw.githubusercontent.com/arikuschi/Pavlonya-OS/main/popos/abbild-zurueck.sh
#   sudo bash abbild-zurueck.sh
set -euo pipefail

NFS_PFAD="/mnt/pavlonya-data/backups/linux"
MNT=/var/mnt/popos-abbild
WERKZEUG=localhost/pavlonya-abbild-werkzeug

[[ ${EUID} -eq 0 ]] || { echo "Bitte mit sudo starten:  sudo bash abbild-zurueck.sh"; exit 1; }
BENUTZER="${SUDO_USER:-}"
[[ -n "${BENUTZER}" && "${BENUTZER}" != root ]] || read -rp "Benutzer, dem die Abbilder gehören (z. B. arikushi): " BENUTZER
GID="$(id -g "${BENUTZER}")"
als_benutzer() { setpriv --reuid="${BENUTZER}" --regid="${GID}" --init-groups "$@"; }

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

read -rp "TrueNAS-Adresse (IP, steht im Vault unter „Homelab Pavlonya“): " NAS
mkdir -p "${MNT}"
EINGEHAENGT=0
mountpoint -q "${MNT}" || { mount -t nfs -o ro,soft,timeo=150,retrans=3 "${NAS}:${NFS_PFAD}" "${MNT}"; EINGEHAENGT=1; }
trap '[[ ${EINGEHAENGT} == 1 ]] && umount "${MNT}"' EXIT

# --- Welches Abbild? Vorschlag: das neueste
mapfile -t ABBILDER < <(als_benutzer bash -c "ls -d '${MNT}'/popos-abbild-* 2> /dev/null" | sort)
(( ${#ABBILDER[@]} > 0 )) || { echo "Kein Abbild unter ${MNT} gefunden."; exit 1; }
echo "Vorhandene Abbilder:"; printf '  %s\n' "${ABBILDER[@]##*/}"
read -rp "Welches? [Enter = ${ABBILDER[-1]##*/}] " wahl
QUELLE="${MNT}/${wahl:-${ABBILDER[-1]##*/}}"
als_benutzer test -f "${QUELLE}/SHA256SUMS" || { echo "${QUELLE} ist unvollständig (keine SHA256SUMS)."; exit 1; }
echo "Prüfsummen prüfen (liest das ganze Abbild, dauert) …"
als_benutzer bash -c "cd '${QUELLE}' && sha256sum --quiet -c SHA256SUMS" || { echo "Abbild beschädigt — Abbruch."; exit 1; }
QUELLE_INFO="$(als_benutzer cat "${QUELLE}/info.txt")"
info() { sed -n "s/^$1=//p" <<< "${QUELLE_INFO}"; }

# --- Zielplatte: bevorzugt dieselbe wie beim Sichern (Seriennummer)
ZIEL=""
for d in $(lsblk -dnpo NAME,TYPE | awk '$2 == "disk" {print $1}'); do
    [[ "$(lsblk -dno SERIAL "${d}" | xargs)" == "$(info seriennummer)" ]] && ZIEL="${d}"
done
echo "Gesichert von: $(info modell), Seriennummer $(info seriennummer), $(( $(info groesse) / 10**9 )) GB, am $(info datum)"
lsblk -dpo NAME,MODEL,SERIAL,SIZE | grep -v loop
read -rp "Zielplatte [Enter = ${ZIEL:-keine erkannt}]: " eingabe
ZIEL="${eingabe:-${ZIEL}}"
[[ -b "${ZIEL}" && "$(lsblk -dno TYPE "${ZIEL}")" == disk ]] || { echo "${ZIEL} ist keine Platte."; exit 1; }
if lsblk -nlo MOUNTPOINTS "${ZIEL}" | grep -q .; then
    echo "Auf ${ZIEL} ist etwas eingehängt (läuft dieses System von dort?) — Abbruch."; exit 1
fi
(( $(lsblk -bdno SIZE "${ZIEL}") >= $(info groesse) )) || { echo "${ZIEL} ist kleiner als die gesicherte Platte."; exit 1; }

echo
echo "ACHTUNG: ${ZIEL} ($(lsblk -dno MODEL,SIZE "${ZIEL}" | xargs)) wird KOMPLETT überschrieben:"
lsblk -o NAME,SIZE,FSTYPE,LABEL "${ZIEL}"
read -rp "Zum Bestätigen den Namen der Platte eintippen ($(basename "${ZIEL}")): " ok
[[ "${ok}" == "$(basename "${ZIEL}")" ]] || { echo "Abgebrochen, nichts verändert."; exit 1; }

werkzeug

# --- Partitionstabelle, dann jede Partition
wipefs -a -q "${ZIEL}"
als_benutzer cat "${QUELLE}/tabelle.sfdisk" | sfdisk -q "${ZIEL}"
partprobe "${ZIEL}" 2> /dev/null || true
udevadm settle
declare -A PART
for p in $(lsblk -nlpo NAME,TYPE "${ZIEL}" | awk '$2 == "part" {print $1}'); do PART[$(partnr "${p}")]="${p}"; done

while read -r nr fs datei; do
    [[ "${fs}" == leer ]] && { echo "Partition ${nr}: nur angelegt (Swap legt Pop!_OS beim Start an)"; continue; }
    p="${PART[${nr}]:-}"
    [[ -n "${p}" ]] || { echo "FEHLER: Partition ${nr} fehlt nach dem Anlegen der Tabelle."; exit 1; }
    echo "--- Partition ${nr} (${fs}) ← ${datei}"
    # alte Kennungen (z. B. btrfs von Pavlonya OS) weg — partclone schreibt nur belegte
    # Blöcke, eine stehengebliebene Kennung machte die Partition mehrdeutig
    wipefs -a -q "${p}"
    als_benutzer cat "${QUELLE}/${datei}" \
        | im_werkzeug bash -o pipefail -c "zstd -dc | partclone.${fs} -r -s - -O ${p} -L /dev/null"
done < <(als_benutzer cat "${QUELLE}/partitionen.txt")

# --- Kontrolle der Systempartition (nur lesen)
while read -r nr fs datei; do
    [[ "${fs}" == ext4 ]] || continue
    e2fsck -fn "${PART[${nr}]}" > /dev/null 2>&1 && echo "ext4 Partition ${nr}: in Ordnung" \
        || echo "WARNUNG: e2fsck meldet Fehler auf Partition ${nr}"
done < <(als_benutzer cat "${QUELLE}/partitionen.txt")

# --- Starteintrag der Firmware für Pop!_OS (die Installation eines anderen Systems
# kann ihn entfernt haben). Gesichert war z. B.:
#   Boot0002* Pop!_OS 24.04 LTS  HD(1,GPT,<uuid>,…)/File(\EFI\systemd\systemd-bootx64.efi)
EINTRAG="$(als_benutzer cat "${QUELLE}/efiboot.txt" 2> /dev/null | grep -m1 'Pop!_OS' || true)"
if [[ -n "${EINTRAG}" ]] && ! efibootmgr | grep -q 'Pop!_OS'; then
    name="$(sed -E 's/^Boot[0-9A-F]{4}\*? //; s/\t.*//; s/  +HD\(.*//' <<< "${EINTRAG}")"
    esp="$(sed -nE 's/.*HD\(([0-9]+),GPT.*/\1/p' <<< "${EINTRAG}")"
    lader="$(sed -nE 's/.*File\(([^)]*)\).*/\1/p' <<< "${EINTRAG}")"
    efibootmgr -q -c -d "${ZIEL}" -p "${esp}" -L "${name}" -l "${lader}" \
        && echo "Starteintrag „${name}“ angelegt" || echo "WARNUNG: Starteintrag nicht angelegt — Pop!_OS über F12 wählen"
fi

echo
echo "=== Fertig. Neu starten; Pop!_OS ist im Stand vom $(info datum)."
