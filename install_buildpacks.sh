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
PACK_VERSION="${PACK_VERSION:-latest}"
INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"
REQUIRE_CHECKSUM="${REQUIRE_CHECKSUM:-0}"
TMP_DIR=""

GITHUB_REPO="buildpacks/pack"
GITHUB_API_URL="https://api.github.com/repos/${GITHUB_REPO}/releases"

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

    for cmd in curl tar; do
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

    # Restrict to amd64 explicitly as requested
    case "$ARCH" in
        x86_64) ARCH="amd64" ;;
        *)
            log_error "Unsupported architecture: $ARCH. This script only supports amd64."
            exit 1
            ;;
    esac

    log_info "Detected OS: $OS, Architecture: $ARCH"
}

#------------------#
# Fetch Latest Version
#------------------#
fetch_latest_version() {
    log_info "Fetching latest pack version..."

    PACK_VERSION=$(curl -fsSL "${GITHUB_API_URL}/latest" \
        | grep '"tag_name":' | sed -E 's/.*"v?([^"]+)".*/\1/') || {
            log_error "Failed to fetch the latest version from GitHub."
            exit 1
        }

    log_info "Latest version detected: v${PACK_VERSION}"
}

#------------------#
# Download pack
#------------------#
download_pack() {
    TMP_DIR=$(mktemp -d)
    cd "${TMP_DIR}"

    # For pack, Linux AMD64 binaries are typically named: pack-vX.Y.Z-linux.tgz
    FILENAME="pack-v${PACK_VERSION}-linux.tgz"
    DOWNLOAD_URL="https://github.com/${GITHUB_REPO}/releases/download/v${PACK_VERSION}/${FILENAME}"

    log_info "Downloading pack archive: ${DOWNLOAD_URL}"
    curl -fsSLO "${DOWNLOAD_URL}" || {
        log_error "Failed to download pack archive."
        exit 1
    }

    if command -v sha256sum &>/dev/null; then
        # Check for checksums file with a common naming convention
        CHECKSUM_URL="https://github.com/${GITHUB_REPO}/releases/download/v${PACK_VERSION}/pack-v${PACK_VERSION}-checksums.txt"

        log_info "Checking if checksum file exists..."
        if curl --silent --head --fail "${CHECKSUM_URL}" > /dev/null; then
            log_info "Downloading checksum file..."
            curl -fsSLO "${CHECKSUM_URL}" || {
                log_warn "Checksum file could not be downloaded. Continuing without verification."
                return
            }

            log_info "Verifying checksum..."
            if grep "  ${FILENAME}\$" "pack-v${PACK_VERSION}-checksums.txt" | sha256sum -c -; then
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
# Install pack
#------------------#
install_pack() {
    log_info "Extracting pack..."
    tar -xzf "pack-v${PACK_VERSION}-linux.tgz" || {
        log_error "Failed to extract pack archive."
        exit 1
    }

    # After extraction, 'pack' binary should be present in the current directory
    if [[ ! -f "pack" ]]; then
        log_error "pack binary not found after extraction."
        exit 1
    fi

    chmod +x pack

    log_info "Installing pack to ${INSTALL_DIR} (sudo may be required)..."
    sudo mv pack "${INSTALL_DIR}/pack" || {
        log_error "Failed to move pack binary to ${INSTALL_DIR}."
        exit 1
    }

    log_info "pack installed successfully at ${INSTALL_DIR}/pack"
}

#------------------#
# Verify pack Installation
#------------------#
verify_installation() {
    log_info "Verifying pack installation..."

    if ! command -v pack &>/dev/null; then
        log_error "pack command not found in PATH after installation!"
        exit 1
    fi

    if ! pack --version &>/dev/null; then
        log_error "pack failed to run properly after installation!"
        exit 1
    fi

    log_info "pack is installed and working!"
    pack --version
}

#------------------#
# Main Function
#------------------#
main() {
    check_dependencies
    detect_platform

    if [[ "${PACK_VERSION}" == "latest" ]]; then
        fetch_latest_version
    fi

    download_pack
    install_pack
    verify_installation

    log_info "Installation complete. You can now run 'pack'."
}

main "$@"

