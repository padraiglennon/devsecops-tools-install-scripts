#!/bin/bash

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

# 1. Get the latest version via the github.com releases/latest redirect (no API
# token, not rate-limited). kustomize tags are namespaced as kustomize/vX.Y.Z;
# strip the prefix to leave vX.Y.Z for comparison with the installed version.
LOCATION=$(retry_curl -sI -o /dev/null -w '%{redirect_url}' "https://github.com/kubernetes-sigs/kustomize/releases/latest")
LATEST_VERSION="${LOCATION##*/releases/tag/}"
LATEST_VERSION="${LATEST_VERSION##*/}"   # drop any kustomize/ namespace prefix
if [ -z "$LATEST_VERSION" ] || [ "$LATEST_VERSION" = "$LOCATION" ]; then
    echo "[ERROR] Could not resolve the latest kustomize version (network error or no published release)." >&2
    exit 1
fi

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
retry_curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash

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
