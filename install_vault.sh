#!/bin/bash
set -e

# Configuration
BIN_DIR="/usr/local/bin"
ARCH="amd64"
TMP_DIR=$(mktemp -d)

trap 'rm -rf "$TMP_DIR"' EXIT

# Abort cleanly on Ctrl-C (SIGINT) / SIGTERM: print a notice, then re-raise with
# the signal's default disposition so the script exits 130/143 and the EXIT trap
# above still removes the temp dir.
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

echo "🔍 Checking for latest Vault..."
LATEST_VERSION=$(retry_curl -s https://checkpoint-api.hashicorp.com/v1/check/vault | jq -r .current_version)

# Version Check
if [ -f "$BIN_DIR/vault" ]; then
    CURRENT_VERSION=$("$BIN_DIR/vault" version | cut -d ' ' -f 2 | sed 's/v//' | head -n 1)
    if [ "$LATEST_VERSION" == "$CURRENT_VERSION" ]; then
        echo "✅ Vault v$CURRENT_VERSION is already up to date."
        exit 0
    fi
fi

echo "🆕 Updating to v$LATEST_VERSION..."
retry_curl -sL "https://releases.hashicorp.com/vault/${LATEST_VERSION}/vault_${LATEST_VERSION}_linux_${ARCH}.zip" -o "$TMP_DIR/vault.zip"

unzip -q -o "$TMP_DIR/vault.zip" -d "$TMP_DIR"
sudo mv "$TMP_DIR/vault" "$BIN_DIR/"
sudo chmod +x "$BIN_DIR/vault"

echo "🚀 Vault v$LATEST_VERSION installed successfully!"
