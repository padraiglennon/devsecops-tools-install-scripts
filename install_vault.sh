#!/bin/bash
set -e

# Configuration
BIN_DIR="/usr/local/bin"
ARCH="amd64"
TMP_DIR=$(mktemp -d)

trap 'rm -rf "$TMP_DIR"' EXIT

echo "🔍 Checking for latest Vault..."
LATEST_VERSION=$(curl -s https://checkpoint-api.hashicorp.com/v1/check/vault | jq -r .current_version)

# Version Check
if [ -f "$BIN_DIR/vault" ]; then
    CURRENT_VERSION=$("$BIN_DIR/vault" version | cut -d ' ' -f 2 | sed 's/v//' | head -n 1)
    if [ "$LATEST_VERSION" == "$CURRENT_VERSION" ]; then
        echo "✅ Vault v$CURRENT_VERSION is already up to date."
        exit 0
    fi
fi

echo "🆕 Updating to v$LATEST_VERSION..."
curl -sL "https://releases.hashicorp.com/vault/${LATEST_VERSION}/vault_${LATEST_VERSION}_linux_${ARCH}.zip" -o "$TMP_DIR/vault.zip"

unzip -q -o "$TMP_DIR/vault.zip" -d "$TMP_DIR"
sudo mv "$TMP_DIR/vault" "$BIN_DIR/"
sudo chmod +x "$BIN_DIR/vault"

echo "🚀 Vault v$LATEST_VERSION installed successfully!"
