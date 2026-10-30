# Pop!_OS — Backup und Wiederherstellung nach Neuinstallation

Für den Weg von Pavlonya OS zurück zu Pop!_OS: Pop!_OS neu
installieren, dann **ein Befehl**, und Programme, VPN, Laufwerke, Backup-Dienst,
Einstellungen und Daten sind zurück. Keine Geheimnisse in diesen Dateien — Schlüssel
und Kennwörter kommen nur aus dem verschlüsselten restic-Backup auf der TrueNAS.

## Einmal einrichten (laufendes Pop!_OS)

    sudo bash popos/einrichten.sh
    sudo systemctl start popos-backup && cat /var/lib/popos-backup/status

Ersetzt den alten cron-Eintrag (`Scripts/restic-backup.sh`) durch `popos-backup.timer`
(0:00, wird nachgeholt). Gesichert wird das **ganze Home** ohne Neuladbares
(Zwischenspeicher, Flatpak-Programme, Podman-Images, Papierkorb, Steam) und die
Systemteile, die eine Neuinstallation nicht mitbringt: VPN/WLAN (`/etc/netplan`),
Netzlaufwerke, Storage-Box-Schlüssel (`/root/.ssh`), Fremdquellen, Modul-Regeln
(`amdgpu` vor `nvidia`), `fuse.conf`, Drucker, SSH-Server mit Host-Schlüsseln,
Bluetooth-Kopplungen. Dazu eine Programmliste: selbst installierte Pakete, Flatpaks,
Programme ohne Paket (Claude Code, rclone) und der Grafikmodus von `system76-power`.
Die Listen stehen im Skript; eine neue Fassung wirkt nach `sudo bash popos/einrichten.sh`.

## Nach einer Neuinstallation von Pop!_OS

    curl -fsSL https://raw.githubusercontent.com/arikuschi/Pavlonya-OS/main/popos/wiederherstellen.sh | sudo bash

Fragt nach TrueNAS-Adresse und restic-Kennwort, dann: Fremdquellen → Programme →
VPN/WLAN → Laufwerke → System-Einstellungen (Grafik, Drucker, SSH, Bluetooth, FUSE) →
Backup-Dienst → Home. Danach neu starten — erst dann gelten Grafikmodus und Modul-Regeln.
Ersetzte Vorgaben der Neuinstallation bleiben als `*.neuinstallation` liegen.

## Abbild der ganzen Platte (vor dem Überschreiben)

Die Dateisicherung oben bringt neuere Programmversionen und lädt Steam-Spiele neu. Für
einen Rückweg auf exakt den gesicherten Stand: Abbild der Pop!_OS-Platte auf die TrueNAS —
Partitionstabelle samt UUIDs, EFI-, Recovery- und Systempartition (partclone, nur
belegte Blöcke, zstd), danach vollständig geprüft. Läuft unter einem anderen System
(Pavlonya OS auf der zweiten Platte), Pop!_OS darf nicht laufen:

    curl -fsSLO https://raw.githubusercontent.com/arikuschi/Pavlonya-OS/main/popos/abbild-sichern.sh
    sudo bash abbild-sichern.sh

Zurück (überschreibt die Zielplatte komplett, legt den Firmware-Starteintrag neu an):

    curl -fsSLO https://raw.githubusercontent.com/arikuschi/Pavlonya-OS/main/popos/abbild-zurueck.sh
    sudo bash abbild-zurueck.sh

partclone holen beide Skripte einmalig in einem Fedora-Container.

## Technik

restic läuft als Benutzer (Besitzer des Repos auf der TrueNAS) mit dem Zusatzrecht
`CAP_DAC_READ_SEARCH` — so liest es auch root-geschützte Dateien, ohne dass root auf
der NFS-Freigabe Rechte braucht.
