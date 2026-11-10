# Schlüssel

Hierher gehören nur öffentliche Schlüssel: **`cosign.pub`** (eigener, zum Signieren des Images) und
`ublue-akmods.pub` (`cosign.pub` aus ublue-os/akmods — der Bau nimmt die NVIDIA-Module nur mit dieser
Signatur). Der private
Schlüssel `cosign.key` kommt als Secret `SIGNING_SECRET` nach GitHub und
**niemals** ins Repo (steht in .gitignore).

Erzeugen (im Projektordner):

    podman run --rm -it -v ./keys:/keys:z -w /keys \
        gcr.io/projectsigstore/cosign:latest generate-key-pair

Ohne Passwort erzeugen (Enter, Enter) — der Workflow signiert ohne Passwortabfrage.
