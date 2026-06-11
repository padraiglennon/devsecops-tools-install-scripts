#!/bin/bash

# 1. Get the latest version from GitHub API
LATEST_VERSION=$(curl -s "https://api.github.com/repos/kubernetes-sigs/kustomize/releases/latest" | grep -oP '"tag_name":\s*"(kustomize/)?\K[^"]+' | head -n 1)

# 2. Check if kustomize is already installed and compare versions
if command -v kustomize >/dev/null 2>&1; then
    # Removed --short to avoid deprecation warnings
    CURRENT_VERSION=$(kustomize version | grep -oP 'v[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)

    if [ "$CURRENT_VERSION" == "$LATEST_VERSION" ]; then
        echo "Kustomize is already up to date ($CURRENT_VERSION)."
        exit 0
    else
        echo "Updating Kustomize: $CURRENT_VERSION -> $LATEST_VERSION"
    fi
else
    echo "Kustomize not found. Installing latest version: $LATEST_VERSION"
fi

# 3. Download and install using official script
# This script downloads a 'kustomize' binary to the current directory
curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash

# 4. Move to /usr/local/bin and clean up the downloaded binary
if [ -f "kustomize" ]; then
    echo "Installing kustomize to /usr/local/bin..."
    sudo mv kustomize /usr/local/bin/kustomize
    sudo chmod +x /usr/local/bin/kustomize
    echo "Successfully installed: $(kustomize version | grep -oP 'v[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)"
else
    echo "Error: Kustomize binary not found in current directory."
    exit 1
fi
