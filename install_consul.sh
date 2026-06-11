#!/bin/bash
set -e

# Configuration
BIN_DIR="/usr/local/bin"
ARCH="amd64"
TMP_DIR=$(mktemp -d)

trap 'rm -rf "$TMP_DIR"' EXIT

echo "🔍 Checking for latest Consul..."
LATEST_VERSION=$(curl -s https://checkpoint-api.hashicorp.com/v1/check/consul | jq -r .current_version)

# Version Check
if [ -f "$BIN_DIR/consul" ]; then
    CURRENT_VERSION=$("$BIN_DIR/consul" version | grep "Consul v" | cut -d 'v' -f 2)
    if [ "$LATEST_VERSION" == "$CURRENT_VERSION" ]; then
        echo "✅ Consul v$CURRENT_VERSION is already up to date."
        exit 0
    fi
fi

echo "🆕 Updating to v$LATEST_VERSION..."
curl -sL "https://releases.hashicorp.com/consul/${LATEST_VERSION}/consul_${LATEST_VERSION}_linux_${ARCH}.zip" -o "$TMP_DIR/consul.zip"

unzip -q -o "$TMP_DIR/consul.zip" -d "$TMP_DIR"
sudo mv "$TMP_DIR/consul" "$BIN_DIR/"
sudo chmod +x "$BIN_DIR/consul"

echo "🚀 Consul v$LATEST_VERSION installed successfully!"
