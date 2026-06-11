#!/bin/bash

set -euo pipefail

#------------------#
# Logging Functions
#------------------#
log_info() { echo -e "[INFO] $*"; }
log_warn() { echo -e "[WARN] $*" >&2; }
log_error() { echo -e "[ERROR] $*" >&2; }

#------------------#
# Config Variables
#------------------#
HELM_VERSION="${HELM_VERSION:-latest}"
INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"
REQUIRE_CHECKSUM="${REQUIRE_CHECKSUM:-0}"
TMP_DIR=""

#------------------#
# Cleanup
#------------------#
cleanup() {
    if [[ -n "${TMP_DIR}" && -d "${TMP_DIR}" ]]; then
        log_info "Cleaning up temporary files..."
        rm -rf "${TMP_DIR}"
    fi
}
trap cleanup EXIT

#------------------#
# Check Dependencies
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

    case "$ARCH" in
        x86_64) ARCH="amd64" ;;
        arm64|aarch64) ARCH="arm64" ;;
        *)
            log_error "Unsupported architecture: $ARCH"
            exit 1
            ;;
    esac

    if [[ "$OS" != "linux" ]]; then
        log_error "Only Linux OS is supported by this script."
        exit 1
    fi

    log_info "Detected OS: $OS, Architecture: $ARCH"
}

#------------------#
# Fetch Latest Version
#------------------#
fetch_latest_version() {
    log_info "Fetching latest helm version..."

    HELM_VERSION=$(curl -fsSL https://api.github.com/repos/helm/helm/releases/latest \
        | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/') || {
            log_error "Failed to fetch the latest Helm version from GitHub."
            exit 1
        }

    log_info "Latest version detected: v${HELM_VERSION}"
}

#------------------#
# Download Helm
#------------------#
download_helm() {
    TMP_DIR=$(mktemp -d)
    cd "${TMP_DIR}"

    FILENAME="helm-v${HELM_VERSION}-${OS}-${ARCH}.tar.gz"
    DOWNLOAD_URL="https://get.helm.sh/${FILENAME}"
    CHECKSUM_URL="https://get.helm.sh/${FILENAME}.sha256sum"

    log_info "Downloading Helm archive: $DOWNLOAD_URL"
    curl -fsSLO "${DOWNLOAD_URL}" || {
        log_error "Failed to download Helm archive."
        exit 1
    }

    if command -v sha256sum &>/dev/null; then
        log_info "Checking if checksum file is available..."

        if curl --silent --head --fail "${CHECKSUM_URL}" > /dev/null; then
            curl -fsSLO "${CHECKSUM_URL}" || {
                log_warn "Checksum file could not be downloaded. Continuing without verification."
                return
            }

            log_info "Verifying checksum..."
            sha256sum -c "${FILENAME}.sha256sum" || {
                log_error "Checksum verification failed!"
                exit 1
            }

            log_info "Checksum verification passed."
        else
            if [[ "$REQUIRE_CHECKSUM" -eq 1 ]]; then
                log_error "Checksum not available but REQUIRE_CHECKSUM=1. Aborting."
                exit 1
            else
                log_warn "No checksum file found. Skipping verification."
            fi
        fi
    fi
}

#------------------#
# Install Helm
#------------------#
install_helm() {
    log_info "Extracting Helm..."

    tar -xzf "helm-v${HELM_VERSION}-${OS}-${ARCH}.tar.gz" || {
        log_error "Failed to extract Helm archive."
        exit 1
    }

    chmod +x "${OS}-${ARCH}/helm"

    log_info "Installing Helm to ${INSTALL_DIR} (sudo may be required)..."
    sudo mv "${OS}-${ARCH}/helm" "${INSTALL_DIR}/helm" || {
        log_error "Failed to move Helm binary to ${INSTALL_DIR}."
        exit 1
    }

    log_info "Helm installed successfully at ${INSTALL_DIR}/helm"
}

#------------------#
# Verify Helm
#------------------#
verify_installation() {
    log_info "Verifying helm installation..."

    if ! command -v helm &>/dev/null; then
        log_error "helm command not found in PATH after installation!"
        exit 1
    fi

    if ! helm version &>/dev/null; then
        log_error "helm failed to run properly after installation!"
        exit 1
    fi

    log_info "Helm is installed and working!"
    helm version
}

#------------------#
# Main Entry Point
#------------------#
main() {
    check_dependencies
    detect_platform

    if [[ "${HELM_VERSION}" == "latest" ]]; then
        fetch_latest_version
    fi

    download_helm
    install_helm
    verify_installation

    log_info "Installation complete. You can now run 'helm'."
}

main "$@"

