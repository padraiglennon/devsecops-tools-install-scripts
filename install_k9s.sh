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
K9S_VERSION="${K9S_VERSION:-latest}"
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
    log_info "Fetching latest k9s version..."

    # Resolve via the github.com releases/latest redirect (no API token, not
    # rate-limited). Location is .../releases/tag/vX.Y.Z; strip to a bare semver.
    local location
    location=$(retry_curl -sI -o /dev/null -w '%{redirect_url}' \
        "https://github.com/derailed/k9s/releases/latest") || true
    K9S_VERSION="${location##*/releases/tag/v}"

    if [[ -z "$K9S_VERSION" || "$K9S_VERSION" == "$location" ]]; then
        log_error "Failed to resolve the latest k9s version (network error or no published release)."
        exit 1
    fi

    log_info "Latest version detected: v${K9S_VERSION}"
}

#------------------#
# Download K9s
#------------------#
download_k9s() {
    TMP_DIR=$(mktemp -d)
    cd "${TMP_DIR}"

    FILENAME="k9s_Linux_${ARCH}.tar.gz"
    DOWNLOAD_URL="https://github.com/derailed/k9s/releases/download/v${K9S_VERSION}/${FILENAME}"

    log_info "Downloading k9s archive: $DOWNLOAD_URL"
    retry_curl -fsSLO "${DOWNLOAD_URL}" || {
        log_error "Failed to download k9s archive."
        exit 1
    }

    if command -v sha256sum &>/dev/null; then
        CHECKSUM_URL="https://github.com/derailed/k9s/releases/download/v${K9S_VERSION}/checksums.txt"

        log_info "Checking if checksum file exists..."
        if retry_curl --silent --head --fail "${CHECKSUM_URL}" > /dev/null; then
            log_info "Downloading checksum file..."
            retry_curl -fsSLO "${CHECKSUM_URL}" || {
                log_warn "Checksum file could not be downloaded. Continuing without verification."
                return
            }

            log_info "Verifying checksum..."
            if grep "${FILENAME}" checksums.txt | sha256sum -c -; then
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
# Install K9s
#------------------#
install_k9s() {
    log_info "Extracting k9s..."
    tar -xzf "k9s_Linux_${ARCH}.tar.gz" || {
        log_error "Failed to extract k9s archive."
        exit 1
    }

    chmod +x k9s

    log_info "Installing k9s to ${INSTALL_DIR} (sudo may be required)..."
    sudo mv k9s "${INSTALL_DIR}/k9s" || {
        log_error "Failed to move k9s binary to ${INSTALL_DIR}."
        exit 1
    }

    log_info "k9s installed successfully at ${INSTALL_DIR}/k9s"
}

#------------------#
# Verify K9s Installation
#------------------#
verify_installation() {
    log_info "Verifying k9s installation..."

    if ! command -v k9s &>/dev/null; then
        log_error "k9s command not found in PATH after installation!"
        exit 1
    fi

    if ! k9s version &>/dev/null; then
        log_error "k9s failed to run properly after installation!"
        exit 1
    fi

    log_info "k9s is installed and working!"
    k9s version
}

#------------------#
# Main Function
#------------------#
main() {
    check_dependencies
    detect_platform

    if [[ "${K9S_VERSION}" == "latest" ]]; then
        fetch_latest_version
    fi

    download_k9s
    install_k9s
    verify_installation

    log_info "Installation complete. You can now run 'k9s'."
}

main "$@"

