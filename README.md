# Pavlonya OS

Eigenes Fedora-Atomic-Image (bootc) mit COSMIC für den Acer Nitro AN517-41.
Planung, Entscheidungen und Stand: Obsidian-Vault, Notiz **Pavlonya OS**.

## Aufbau

| Pfad | Inhalt |
|---|---|
| `Containerfile` | Basis `fedora-bootc:44` + NVIDIA aus `ublue-os/akmods-nvidia-open` |
| `build_files/` | Build-Schritte in Reihenfolge: Quellen → Kernel/NVIDIA → Pakete → Tabby → System → initramfs → Aufräumen |
| `packages/*.txt` | Native Pakete, ein Paket pro Zeile |
| `system_files/usr/share/pavlonya-os/flatpaks.txt` | Flatpaks, werden beim Start nachinstalliert |
| `system_files/usr/share/pavlonya-os/distrobox.ini` | Distroboxen (Claude Desktop, Entwicklung) |
| `disk_config/` | Installations-ISO (`iso.toml`) und VM-Abbild (`vm.toml.example`) |
| `scripts/` | Lokal bauen, ISO bauen, VM-Abbild bauen |
| `keys/cosign.pub` | Öffentlicher Signaturschlüssel (kommt ins Image) |
| `.github/workflows/build.yml` | Täglicher Bau → ghcr.io, signiert mit cosign |

## Programme ändern

- **Natives Paket:** Zeile in `packages/*.txt`, committen, pushen → neues Image,
  aktiv nach dem nächsten Neustart.
- **Flatpak:** Zeile in `flatpaks.txt` — oder einfach über COSMIC Store installieren.
- **Werkzeug mit häufigen Versionswechseln:** in die Distrobox `dev`.

## Bauen

Lokal (zum Testen):

    scripts/build-local.sh
    scripts/build-iso.sh          # Installations-ISO → output/pavlonya-os-44.iso
    scripts/build-vm.sh           # qcow2 für Proxmox-VM 950

Normal: Push nach GitHub → der Workflow baut, lädt nach
`ghcr.io/<github-name>/pavlonya-os` und signiert.

## Installieren

1. ISO bauen, auf USB-Stick schreiben, Laptop davon starten (F12-Bootmenü).
2. Im Installer **nur die Samsung 850 EVO** auswählen, Partitionen selbst
   festlegen, eigene EFI-Partition auf dieser Platte.
3. Kein Umschalten nötig: Die ISO entsteht aus `ghcr.io/<github-name>/pavlonya-os:44`,
   Updates kommen von dort (`sudo bootc status` zeigt das Image). Die Signatur prüft
   `/etc/containers/policy.json` — für dieses Image `sigstoreSigned` mit
   `/etc/pki/containers/pavlonya-os.pub`, für alle anderen (Distrobox, Podman) „annehmen“.
   bootc wendet die Regel bei jedem Update an. `bootc switch --enforce-container-sigpolicy`
   verweigert sich bei dieser Grundregel und wird nicht gebraucht. Ansehen:

       podman image trust show

4. Distroboxen anlegen:

       distrobox assemble create --file /usr/share/pavlonya-os/distrobox.ini

5. Secure Boot ist am Nitro aus (geprüft 11.10.2026). Die NVIDIA-Module sind mit dem
   Universal-Blue-Schlüssel signiert (Signer „ublue kernel“); der Schlüssel liegt nicht
   im Image. Soll Secure Boot an, vorher den öffentlichen Schlüssel aus ublue-os/akmods
   holen und mit `mokutil --import` registrieren.

## Backup und Neuinstallation

- `pavlonya-backup.timer` sichert täglich 0:00 mit restic auf die TrueNAS.
  Einstellungen nur lokal: `/etc/pavlonya-os/backup.conf` (Vorlage
  `/usr/share/pavlonya-os/backup.conf.example`) und `restic-passwort`.
- Nach einer Neuinstallation: `sudo pavlonya-wiederherstellen` — fragt nach
  TrueNAS-Adresse und restic-Kennwort und holt VPN-Verbindungen,
  Backup-Einstellungen und SSH-Schlüssel aus der letzten Sicherung zurück.
  Auf Nachfrage zusätzlich Programm-Einstellungen aus der Pop!_OS-Sicherung —
  nur was ohne Schlüsselbund funktioniert (Liste `PROGRAMM_EINSTELLUNGEN` im Skript);
  Schlüsselbund und Tabby (eigener Sync) kommen nicht mit.

## Updates

`pavlonya-update.timer` lädt täglich das neue Image; aktiv wird es beim nächsten
Neustart. Zurück zum vorherigen Stand: `sudo bootc rollback`, dann neu starten.

Die Distroboxen (Claude Desktop, `dev`) aktualisiert `pavlonya-distrobox-upgrade.timer`
einmal täglich, solange du angemeldet bist. Von Hand: `distrobox upgrade --all`.
