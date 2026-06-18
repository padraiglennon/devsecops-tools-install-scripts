#!/usr/bin/env bash

set -euo pipefail

# Abort cleanly on Ctrl-C (SIGINT) / SIGTERM: print a notice, then re-raise with
# the signal's default disposition so the script exits 130/143.
_on_signal() { echo >&2; echo "Interrupted - stopping." >&2; trap - "$1"; kill -"$1" "$$"; }
trap '_on_signal INT' INT
trap '_on_signal TERM' TERM

# Determine the latest version
VERSION=$(curl -s https://api.github.com/repos/argoproj/argo-workflows/releases/latest | grep tag_name | cut -d '"' -f 4)

# Download the compressed binary
curl -sLO "https://github.com/argoproj/argo-workflows/releases/download/${VERSION}/argo-linux-amd64.gz"

# Decompress the binary
gunzip "argo-linux-amd64.gz"

# Make it executable
chmod +x "argo-linux-amd64"

# Move to /usr/local/bin
sudo mv "argo-linux-amd64" /usr/local/bin/argo

# Verify installation
argo version

