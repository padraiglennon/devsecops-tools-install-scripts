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

    # Resolve via the github.com releases/latest redirect (no API token, not
    # rate-limited). Location is .../releases/tag/vX.Y.Z; keep the full tag,
    # since eksctl download URLs use the 'v' prefix.
    local location
    location=$(retry_curl -sI -o /dev/null -w '%{redirect_url}' \
        "https://github.com/eksctl-io/eksctl/releases/latest") || true
    EKSCTL_VERSION="${location##*/releases/tag/}"

    if [[ -z "$EKSCTL_VERSION" || "$EKSCTL_VERSION" == "$location" ]]; then
        log_error "Failed to resolve the latest eksctl version (network error or no published release)."
        exit 1
    fi

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
    retry_curl -fsSLO "${DOWNLOAD_URL}" || {
        log_error "Failed to download eksctl archive."
        exit 1
    }

    if command -v sha256sum &>/dev/null; then
        CHECKSUM_URL="https://github.com/eksctl-io/eksctl/releases/download/${EKSCTL_VERSION}/eksctl_checksums.txt"

        log_info "Checking if checksum file exists..."
        if retry_curl --silent --head --fail "${CHECKSUM_URL}" > /dev/null; then
            log_info "Downloading checksum file..."
            retry_curl -fsSLO "${CHECKSUM_URL}" || {
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
