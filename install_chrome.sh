#!/bin/bash

set -euo pipefail

# Abort cleanly on Ctrl-C (SIGINT) / SIGTERM: print a notice, then re-raise with
# the signal's default disposition so the script exits 130/143 and any EXIT trap
# (temp-dir cleanup) still runs.
_on_signal() { echo >&2; echo "Interrupted - stopping." >&2; trap - "$1"; kill -"$1" "$$"; }
trap '_on_signal INT' INT
trap '_on_signal TERM' TERM

#------------------#
# Logging Functions
#------------------#
log_info() { echo -e "[INFO] $*"; }
log_warn() { echo -e "[WARN] $*" >&2; }
log_error() { echo -e "[ERROR] $*" >&2; }

# retry_curl ARGS...  - curl with retry on transient failures (network errors,
# connection timeouts, 5xx). Passes all args through; returns the last exit code.
retry_curl() {
    local attempt=1 delay=3 rc
    while :; do
        curl "$@" && return 0
        rc=$?
        (( rc == 22 )) && return "$rc"   # HTTP 4xx (rate limit/auth/not-found): do not retry
        (( attempt >= 3 )) && return "$rc"
        log_warn "curl failed (exit ${rc}), retry ${attempt}/2 in ${delay}s..."
        sleep "$delay"; attempt=$((attempt + 1)); delay=$((delay * 2))
    done
}

#------------------#
# Default Variables
#------------------#
# Install Google Chrome (stable) via Google's apt repository so subsequent
# `sudo apt update && sudo apt upgrade` picks up new versions automatically.
KEYRING_PATH="/usr/share/keyrings/google-chrome-keyring.gpg"
SOURCES_PATH="/etc/apt/sources.list.d/google-chrome.list"
GOOGLE_KEY_URL="https://dl.google.com/linux/linux_signing_key.pub"
CHROME_REPO="deb [arch=amd64 signed-by=${KEYRING_PATH}] https://dl.google.com/linux/chrome/deb/ stable main"
CHROME_BIN="/opt/google/chrome/chrome"

#------------------#
# Dependency Checks
#------------------#
check_dependencies() {
    log_info "Checking required tools..."

    for cmd in curl gpg sudo apt-get; do
        if ! command -v "${cmd}" &>/dev/null; then
            log_error "Missing required command: ${cmd}. Please install it (e.g., sudo apt install ${cmd})."
            exit 1
        fi
    done
}

#------------------#
# Platform Detection
#------------------#
detect_platform() {
    log_info "Detecting platform..."

    ARCH=$(uname -m)

    case "$ARCH" in
        x86_64)
            log_info "Detected x86_64 — Google Chrome stable is available."
            ;;
        arm64|aarch64)
            log_error "Google Chrome for Linux is not distributed for ${ARCH}. Use Chromium instead."
            exit 1
            ;;
        *)
            log_error "Unsupported architecture: ${ARCH}"
            exit 1
            ;;
    esac

    if ! grep -qiE "ubuntu|debian" /etc/os-release 2>/dev/null; then
        log_warn "Non-Debian/Ubuntu host detected; this script uses apt and may not work."
    fi
}

#------------------#
# Configure apt repository
#------------------#
configure_repo() {
    log_info "Configuring Google Chrome apt repository..."

    # Import / refresh the signing key into a dedicated keyring (modern best practice).
    retry_curl -fsSL "${GOOGLE_KEY_URL}" \
        | sudo gpg --dearmor --yes -o "${KEYRING_PATH}"
    sudo chmod 0644 "${KEYRING_PATH}"

    # Write (or overwrite) the source list so re-runs converge on the canonical line.
    echo "${CHROME_REPO}" | sudo tee "${SOURCES_PATH}" >/dev/null
    sudo chmod 0644 "${SOURCES_PATH}"
}

#------------------#
# Install or upgrade Chrome
#------------------#
install_chrome() {
    log_info "Updating apt indexes..."
    sudo apt-get update -qq

    if dpkg -s google-chrome-stable &>/dev/null; then
        log_info "google-chrome-stable already installed — upgrading if a newer version is available..."
        sudo apt-get install --only-upgrade -y google-chrome-stable
    else
        log_info "Installing google-chrome-stable..."
        sudo apt-get install -y google-chrome-stable
    fi
}

#------------------#
# Verify Installation
#------------------#
verify_installation() {
    log_info "Verifying Chrome installation..."

    if [[ ! -x "${CHROME_BIN}" ]]; then
        log_error "Expected Chrome binary at ${CHROME_BIN} not found."
        exit 1
    fi

    if ! command -v google-chrome &>/dev/null; then
        log_warn "'google-chrome' not found in PATH, but ${CHROME_BIN} exists."
    fi

    log_info "Google Chrome is installed:"
    "${CHROME_BIN}" --version
}

#------------------#
# Main Function
#------------------#
main() {
    check_dependencies
    detect_platform
    configure_repo
    install_chrome
    verify_installation

    log_info "Done. Future upgrades: sudo apt update && sudo apt upgrade google-chrome-stable"
}

main "$@"
