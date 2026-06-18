#!/usr/bin/env bash

set -euo pipefail

# Abort cleanly on Ctrl-C (SIGINT) / SIGTERM: print a notice, then re-raise with
# the signal's default disposition so the script exits 130/143.
_on_signal() { echo >&2; echo "Interrupted - stopping." >&2; trap - "$1"; kill -"$1" "$$"; }
trap '_on_signal INT' INT
trap '_on_signal TERM' TERM

# retry_curl ARGS...  - curl with retry on transient failures (network errors,
# connection timeouts, 5xx). Passes all args through; returns the last exit code.
retry_curl() {
    local attempt=1 delay=3 rc
    while :; do
        curl "$@" && return 0
        rc=$?
        (( rc == 22 )) && return "$rc"   # HTTP 4xx (rate limit/auth/not-found): do not retry
        (( attempt >= 3 )) && return "$rc"
        echo "[WARN] curl failed (exit ${rc}), retry ${attempt}/2 in ${delay}s..." >&2
        sleep "$delay"; attempt=$((attempt + 1)); delay=$((delay * 2))
    done
}

# Determine the latest version via the github.com releases/latest redirect
# (no API token, not rate-limited). Location is .../releases/tag/vX.Y.Z.
LOCATION=$(retry_curl -sI -o /dev/null -w '%{redirect_url}' "https://github.com/argoproj/argo-workflows/releases/latest")
VERSION="${LOCATION##*/releases/tag/}"
if [ -z "$VERSION" ] || [ "$VERSION" = "$LOCATION" ]; then
    echo "[ERROR] Could not resolve the latest argo version (network error or no published release)." >&2
    exit 1
fi

# Download the compressed binary
retry_curl -sLO "https://github.com/argoproj/argo-workflows/releases/download/${VERSION}/argo-linux-amd64.gz"

# Decompress the binary
gunzip "argo-linux-amd64.gz"

# Make it executable
chmod +x "argo-linux-amd64"

# Move to /usr/local/bin
sudo mv "argo-linux-amd64" /usr/local/bin/argo

# Verify installation
argo version

