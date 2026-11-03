# Was gesichert und nach einer Neuinstallation zurückgeholt wird — gelesen von
# pavlonya-backup und pavlonya-wiederherstellen, damit beide dieselbe Liste haben
# (03.11.2026: die Wiederherstellung suchte unter einem anderen Pfad, als gesichert
# wurde). Steht im Image und nicht in backup.conf: Änderungen kommen per bootc upgrade
# an; eine backup.conf aus einer alten Sicherung brachte am 03.11.2026 die alte Liste
# zurück (Monitore, Drucker und der Schlüssel von root fehlten).
#
# Die Liste ist das, was beim Umzug von Pop!_OS zurückgeholt wurde und läuft, dazu der
# Schlüsselbund und .config/git (Arikushi, 03.11.2026). Programme selbst kommen aus dem
# Image bzw. als Flatpak über die Ersteinrichtung — gesichert werden nur ihre
# Einstellungen. Nicht dabei: Bluetooth-Kopplungen, SSH-Rechnerschlüssel (Arikushi,
# 03.11.2026), Downloads (30.10.2026), Steam (13.10.2026).

# Im Home (relativ zum Home)
SICHERUNG_HOME=(
    # Daten (Obsidian-Vault in Dokumente)
    Dokumente Bilder Videos Musik Vorlagen
    wg-pavlonya.key private.key public.key          # lose Schlüsseldateien im Home
    .gitconfig .gnupg .bash_history .bashrc .ssh
    .claude .claude.json                            # Claude Code
    .config/rclone .config/gh .config/systemd/user  # systemd/user: Forgejo-Dump nachts abholen
    .config/git                                     # Hook gegen den Klarnamen in Commits
    # Programm-Einstellungen
    .var/app/one.ablaze.floorp .var/app/com.google.Chrome .var/app/org.chromium.Chromium
    .var/app/org.mozilla.thunderbird .var/app/md.obsidian.Obsidian .var/app/com.mikrotik.WinBox
    .var/app/org.remmina.Remmina .var/app/com.rustdesk.RustDesk .var/app/com.bambulab.BambuStudio
    .var/app/dev.zed.Zed/config/zed .vscode/extensions .config/tabby
    .config/Cryptomator                             # Tresorliste
    # COSMIC: Monitore, Uhr, Tastatur, Energie (Aussehen kommt aus dem Image)
    .local/state/cosmic-comp/outputs.ron
    .config/cosmic/com.system76.CosmicAppletTime
    .config/cosmic/com.system76.CosmicComp/v1/xkb_config
    .config/cosmic/com.system76.CosmicIdle
)
# Nur mit dem Schlüsselbund nutzbar — gesichert immer, zurückgeholt nur bei
# „Schlüsselbund übernehmen: J“. Chrome, Chromium, Obsidian, Bitwarden, Claude Desktop
# und VS Code verschlüsseln Anmeldungen und Kennwörter mit einem Schlüssel daraus
# (geprüft 19.10.2026); Floorp und Thunderbird haben einen eigenen Kennwortspeicher.
SICHERUNG_SCHLUESSELBUND=(
    .local/share/keyrings
    .var/app/com.bitwarden.desktop
    .config/Claude
    .config/Code
)
# Unter den Programm-Ordnern: Zwischenspeicher, Protokolle und die VM-Abbilder von
# Claude Desktop (12 GB, lädt es selbst) nie
OHNE_IMMER=( cache Cache "Code Cache" GPUCache DawnGraphiteCache DawnWebGPUCache .ld.so logs vm_bundles )
# … und ohne Schlüsselbund auch keine Anmeldungen und Kennwortspeicher
OHNE_OHNE_SCHLUESSELBUND=( "Cookies*" "Login Data*" keyrings )
PROGRAMM_ORDNER=( .var/app .config .vscode )

# System
SICHERUNG_SYSTEM=(
    /etc/NetworkManager                             # VPN, WLAN
    /etc/fstab /var/roothome/.ssh                   # Storage Box: Zeile und Schlüssel von root
    /etc/cups/printers.conf /etc/cups/ppd           # Drucker
    /etc/pavlonya-os                                # Backup-Einstellungen und Kennwort
)

# restic-Muster: <Muster> unter allen Programm-Ordnern von <Home>
# ohne_muster <Home> <Name …> → --exclude <Home>/<Ordner>/**/<Name> …
ohne_muster() {
    local home="$1" o n; shift
    for o in "${PROGRAMM_ORDNER[@]}"; do
        for n in "$@"; do printf -- '--exclude\0%s/%s/**/%s\0' "${home}" "${o}" "${n}"; done
    done
}
