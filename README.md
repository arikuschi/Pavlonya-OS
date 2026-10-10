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
    scripts/build-iso.sh          # Installations-ISO aus dem lokalen Image
    scripts/build-vm.sh           # qcow2 für Proxmox-VM 950

Normal: Push nach GitHub → der Workflow baut, lädt nach
`ghcr.io/<github-name>/pavlonya-os` und signiert.

## Installieren

1. ISO bauen, auf USB-Stick schreiben, Laptop davon starten (F12-Bootmenü).
2. Im Installer **nur die Samsung 850 EVO** auswählen, Partitionen selbst
   festlegen, eigene EFI-Partition auf dieser Platte.
3. Nach dem ersten Start auf das signierte Image von GitHub umschalten:

       sudo bootc switch --enforce-container-sigpolicy ghcr.io/<github-name>/pavlonya-os:44

4. Distroboxen anlegen:

       distrobox assemble create --file /usr/share/pavlonya-os/distrobox.ini

5. Secure Boot: Ist es eingeschaltet, den Schlüssel der NVIDIA-Module einmal
   registrieren (Pfad im Image prüfen, vermutlich so):

       sudo mokutil --import /etc/pki/akmods/certs/akmods-ublue.der

## Updates

`pavlonya-update.timer` lädt täglich das neue Image; aktiv wird es beim nächsten
Neustart. Zurück zum vorherigen Stand: `sudo bootc rollback`, dann neu starten.
