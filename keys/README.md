# Schlüssel

Hierher gehört nur **`cosign.pub`** (öffentlicher Schlüssel). Der private
Schlüssel `cosign.key` kommt als Secret `SIGNING_SECRET` nach GitHub und
**niemals** ins Repo (steht in .gitignore).

Erzeugen (im Projektordner):

    podman run --rm -it -v ./keys:/keys:z -w /keys \
        gcr.io/projectsigstore/cosign:latest generate-key-pair

Ohne Passwort erzeugen (Enter, Enter) — der Workflow signiert ohne Passwortabfrage.
