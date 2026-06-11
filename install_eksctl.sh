#!/bin/bash

set -euo pipefail

#------------------#
# Logging Functions
#------------------#
log_info() { echo -e "[INFO] $*"; }
log_warn() { echo -e "[WARN] $*" >&2; }
log_error() { echo -e "[ERROR] $*" >&2; }

#------------------#
# Default Variables
#------------------#
EKSCTL_VERSION="${EKSCTL_VERSION:-latest}"
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

    for cmd in curl tar; do
        if ! command -v "${cmd}" &>/dev/null; then
            log_error "Missing required command: ${cmd}"
            exit 1
        fi
    done
}

#------------------#
# Platform Detection
#------------------#
detect_platform() {
    log_info "Detecting platform..."

    OS=$(uname -s) # eksctl uses capitalized 'Linux' or 'Darwin' in filenames
    ARCH=$(uname -m)

    case "$ARCH" in
        x86_64) ARCH="amd64" ;;
        arm64|aarch64) ARCH="arm64" ;;
        *)
            log_error "Unsupported architecture: $ARCH"
            exit 1
            ;;
    esac

    log_info "Detected OS: $OS, Architecture: $ARCH"
}

#------------------#
# Fetch Latest Version
#------------------#
fetch_latest_version() {
    log_info "Fetching latest eksctl version..."

    # Fetches the tag name and removes the leading 'v' for internal variable use if needed,
    # though eksctl downloads often use the 'v' prefix.
    EKSCTL_VERSION=$(curl -fsSL https://api.github.com/repos/eksctl-io/eksctl/releases/latest \
        | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/') || {
            log_error "Failed to fetch the latest version from GitHub."
            exit 1
        }

    log_info "Latest version detected: ${EKSCTL_VERSION}"
}

#------------------#
# Download eksctl
#------------------#
download_eksctl() {
    TMP_DIR=$(mktemp -d)
    cd "${TMP_DIR}"

    # eksctl format: eksctl_Linux_amd64.tar.gz
    FILENAME="eksctl_${OS}_${ARCH}.tar.gz"
    DOWNLOAD_URL="https://github.com/eksctl-io/eksctl/releases/download/${EKSCTL_VERSION}/${FILENAME}"

    log_info "Downloading eksctl archive: $DOWNLOAD_URL"
    curl -fsSLO "${DOWNLOAD_URL}" || {
        log_error "Failed to download eksctl archive."
        exit 1
    }

    if command -v sha256sum &>/dev/null; then
        CHECKSUM_URL="https://github.com/eksctl-io/eksctl/releases/download/${EKSCTL_VERSION}/eksctl_checksums.txt"

        log_info "Checking if checksum file exists..."
        if curl --silent --head --fail "${CHECKSUM_URL}" > /dev/null; then
            log_info "Downloading checksum file..."
            curl -fsSLO "${CHECKSUM_URL}" || {
                log_warn "Checksum file could not be downloaded. Continuing without verification."
                return
            }

            log_info "Verifying checksum..."
            # eksctl checksums.txt contains the full path/filename
            if grep "${FILENAME}" eksctl_checksums.txt | sha256sum -c -; then
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
# Install eksctl
#------------------#
install_eksctl() {
    log_info "Extracting eksctl..."
    tar -xzf "eksctl_${OS}_${ARCH}.tar.gz" || {
        log_error "Failed to extract eksctl archive."
        exit 1
    }

    chmod +x eksctl

    log_info "Installing eksctl to ${INSTALL_DIR} (sudo may be required)..."
    sudo mv eksctl "${INSTALL_DIR}/eksctl" || {
        log_error "Failed to move eksctl binary to ${INSTALL_DIR}."
        exit 1
    }

    log_info "eksctl installed successfully at ${INSTALL_DIR}/eksctl"
}

#------------------#
# Verify Installation
#------------------#
verify_installation() {
    log_info "Verifying eksctl installation..."

    if ! command -v eksctl &>/dev/null; then
        log_error "eksctl command not found in PATH!"
        exit 1
    fi

    log_info "eksctl is installed and working!"
    eksctl version
}

#------------------#
# Main Function
#------------------#
main() {
    check_dependencies
    detect_platform

    if [[ "${EKSCTL_VERSION}" == "latest" ]]; then
        fetch_latest_version
    fi

    download_eksctl
    install_eksctl
    verify_installation

    log_info "Installation complete."
}

main "$@"
