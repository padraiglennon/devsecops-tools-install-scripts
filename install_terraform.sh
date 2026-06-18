#!/bin/bash
set -e

# Configuration
BIN_DIR="/usr/local/bin"
ARCH="amd64"
TMP_DIR=$(mktemp -d)

# Cleanup trap: Ensures the temp directory is deleted on exit, error, or interrupt
trap 'rm -rf "$TMP_DIR"' EXIT

# Abort cleanly on Ctrl-C (SIGINT) / SIGTERM: print a notice, then re-raise with
# the signal's default disposition so the script exits 130/143 and the EXIT trap
# above still removes the temp dir.
_on_signal() { echo >&2; echo "Interrupted - stopping." >&2; trap - "$1"; kill -"$1" "$$"; }
trap '_on_signal INT' INT
trap '_on_signal TERM' TERM

echo "🔍 Checking for latest Terraform..."
LATEST_VERSION=$(curl -s https://checkpoint-api.hashicorp.com/v1/check/terraform | jq -r .current_version)

# Version Check
if [ -f "$BIN_DIR/terraform" ]; then
    CURRENT_VERSION=$("$BIN_DIR/terraform" version -json | jq -r .terraform_version)
    if [ "$LATEST_VERSION" == "$CURRENT_VERSION" ]; then
        echo "✅ Terraform v$CURRENT_VERSION is already up to date."
        exit 0
    fi
fi

echo "🆕 Updating to v$LATEST_VERSION..."
curl -sL "https://releases.hashicorp.com/terraform/${LATEST_VERSION}/terraform_${LATEST_VERSION}_linux_${ARCH}.zip" -o "$TMP_DIR/terraform.zip"

unzip -q -o "$TMP_DIR/terraform.zip" -d "$TMP_DIR"
# Only move the binary, ignoring the license/readme files
sudo mv "$TMP_DIR/terraform" "$BIN_DIR/"
sudo chmod +x "$BIN_DIR/terraform"

echo "🚀 Terraform v$LATEST_VERSION installed successfully!"
