#!/usr/bin/bash
# Image lokal bauen (Test vor dem Push). Ergebnis: localhost/pavlonya-os:45
set -euxo pipefail
cd "$(dirname "$0")/.."
sudo podman build --pull=newer -t localhost/pavlonya-os:45 .
