# Pop!_OS — Backup und Wiederherstellung nach Neuinstallation

Für den Fall, dass Sergej von Pavlonya OS zurück zu Pop!_OS will: Pop!_OS neu
installieren, dann **ein Befehl**, und Programme, VPN, Laufwerke, Backup-Dienst,
Einstellungen und Daten sind zurück. Keine Geheimnisse in diesen Dateien — Schlüssel
und Kennwörter kommen nur aus dem verschlüsselten restic-Backup auf der TrueNAS.

## Einmal einrichten (laufendes Pop!_OS)

    sudo bash popos/einrichten.sh
    sudo systemctl start popos-backup && cat /var/lib/popos-backup/status

Ersetzt den alten cron-Eintrag (`Scripts/restic-backup.sh`) durch `popos-backup.timer`
(0:00, wird nachgeholt). Gesichert werden zusätzlich VPN/WLAN (`/etc/netplan`),
Storage-Box-Schlüssel (`/root/.ssh`), Netzlaufwerke, Fremdquellen und eine
Programmliste (nur selbst installierte Pakete und Flatpaks).

## Nach einer Neuinstallation von Pop!_OS

    curl -fsSL https://raw.githubusercontent.com/arikuschi/Pavlonya-OS/main/popos/wiederherstellen.sh | sudo bash

Fragt nach TrueNAS-Adresse und restic-Kennwort, dann: Fremdquellen → Programme →
VPN/WLAN → Laufwerke → Backup-Dienst → Einstellungen und Daten. Danach neu starten.

## Technik

restic läuft als Benutzer (Besitzer des Repos auf der TrueNAS) mit dem Zusatzrecht
`CAP_DAC_READ_SEARCH` — so liest es auch root-geschützte Dateien, ohne dass root auf
der NFS-Freigabe Rechte braucht.
