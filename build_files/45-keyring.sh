#!/usr/bin/bash
# 45-keyring.sh — gnome-keyring mit Absturz-Fix einspielen.
# Gebaut in der Stufe „keyring“ (keyring/build.sh); Grund steht dort.
set -euxo pipefail

ls -l /tmp/keyring
dnf -y install /tmp/keyring/gnome-keyring-[0-9]*.rpm /tmp/keyring/gnome-keyring-pam-[0-9]*.rpm

# Beide Pakete müssen aus dem eigenen Bau stammen, und der Fix muss im Daemon stecken
rpm -q gnome-keyring gnome-keyring-pam
test "$(rpm -q gnome-keyring gnome-keyring-pam | grep -c '\.pavlonya\.')" -eq 2
grep -q "Couldn't open a session for this caller" /usr/bin/gnome-keyring-daemon
