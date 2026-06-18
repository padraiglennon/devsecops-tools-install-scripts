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

#------------------#
# Default Variables
#------------------#
ENVOY_VERSION="${ENVOY_VERSION:-latest}"
INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"
REQUIRE_CHECKSUM="${REQUIRE_CHECKSUM:-0}"
TMP_DIR=""

#------------------#
# Cleanup Function
#------------------#
cleanup() {
    if [[ -n "${TMP_DIR}" && -d "${TMP_DIR}" ]]; then
        log_info "Cleaning up temporary files..."
        rm -rf "${TMP_DIR}"
    fi
}
trap cleanup EXIT

#------------------#
# Dependency Checks
#------------------#
check_dependencies() {
    log_info "Checking required tools..."

    for cmd in curl; do
        if ! command -v "${cmd}" &>/dev/null; then
            log_error "Missing required command: ${cmd}"
            exit 1
        fi
    done

    if ! command -v sha256sum &>/dev/null; then
        if [[ "$REQUIRE_CHECKSUM" -eq 1 ]]; then
            log_error "sha256sum is required but not installed."
            exit 1
        else
            log_warn "sha256sum not found, skipping checksum verification."
        fi
    fi
}

#------------------#
# Platform Detection
#------------------#
detect_platform() {
    log_info "Detecting platform..."

    OS=$(uname | tr '[:upper:]' '[:lower:]')
    ARCH=$(uname -m)

    if [[ "$OS" != "linux" ]]; then
        log_error "Only Linux OS is supported by this script."
        exit 1
    fi

    case "$ARCH" in
        x86_64|amd64) ARCH="x86_64" ;;
        *)
            log_error "Unsupported architecture for Linux envoy release: $ARCH (only x86_64 is published)."
            exit 1
            ;;
    esac

    log_info "Detected OS: $OS, Architecture: $ARCH"
}

#------------------#
# Fetch Latest Version
#------------------#
fetch_latest_version() {
    log_info "Fetching latest envoy version..."

    ENVOY_VERSION=$(curl -fsSL https://api.github.com/repos/statecraft-protocol/envoy/releases/latest \
        | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/') || {
            log_error "Failed to fetch the latest version from GitHub."
            exit 1
        }

    log_info "Latest version detected: v${ENVOY_VERSION}"
}

#------------------#
# Download Envoy
#------------------#
download_envoy() {
    TMP_DIR=$(mktemp -d)
    cd "${TMP_DIR}"

    FILENAME="envoy-linux-${ARCH}"
    DOWNLOAD_URL="https://github.com/statecraft-protocol/envoy/releases/download/v${ENVOY_VERSION}/${FILENAME}"

    log_info "Downloading envoy binary: $DOWNLOAD_URL"
    curl -fsSLO "${DOWNLOAD_URL}" || {
        log_error "Failed to download envoy binary."
        exit 1
    }

    if command -v sha256sum &>/dev/null; then
        CHECKSUM_URL="https://github.com/statecraft-protocol/envoy/releases/download/v${ENVOY_VERSION}/SHA256SUMS"

        log_info "Checking if checksum file exists..."
        if curl --silent --head --fail "${CHECKSUM_URL}" > /dev/null; then
            log_info "Downloading checksum file..."
            curl -fsSLO "${CHECKSUM_URL}" || {
                log_warn "Checksum file could not be downloaded. Continuing without verification."
                return
            }

            log_info "Verifying checksum..."
            if grep "${FILENAME}" SHA256SUMS | sha256sum -c -; then
                log_info "Checksum verification passed."
            else
                log_error "Checksum verification failed!"
                exit 1
            fi
        else
            if [[ "$REQUIRE_CHECKSUM" -eq 1 ]]; then
                log_error "Checksum file not available but REQUIRE_CHECKSUM=1. Aborting."
                exit 1
            else
                log_warn "No checksum published for this version. Skipping verification."
            fi
        fi
    fi
}

#------------------#
# Install Envoy
#------------------#
install_envoy() {
    log_info "Preparing envoy binary..."
    mv "envoy-linux-${ARCH}" envoy
    chmod +x envoy

    log_info "Installing envoy to ${INSTALL_DIR} (sudo may be required)..."
    sudo mv envoy "${INSTALL_DIR}/envoy" || {
        log_error "Failed to move envoy binary to ${INSTALL_DIR}."
        exit 1
    }

    log_info "envoy installed successfully at ${INSTALL_DIR}/envoy"
}

#------------------#
# Verify Envoy Installation
#------------------#
verify_installation() {
    log_info "Verifying envoy installation..."

    if ! command -v envoy &>/dev/null; then
        log_error "envoy command not found in PATH after installation!"
        exit 1
    fi

    if envoy --version &>/dev/null; then
        log_info "envoy is installed and working!"
        envoy --version
    elif envoy version &>/dev/null; then
        log_info "envoy is installed and working!"
        envoy version
    else
        log_warn "envoy ran but did not respond to --version/version; binary is in place at ${INSTALL_DIR}/envoy."
    fi
}

#------------------#
# Main Function
#------------------#
main() {
    check_dependencies
    detect_platform

    if [[ "${ENVOY_VERSION}" == "latest" ]]; then
        fetch_latest_version
    fi

    download_envoy
    install_envoy
    verify_installation

    log_info "Installation complete. You can now run 'envoy'."
}

main "$@"
