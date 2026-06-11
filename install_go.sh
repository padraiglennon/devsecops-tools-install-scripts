#!/usr/bin/env bash
# install_go.sh — install/upgrade Go to the latest stable from go.dev.
# Installs into /usr/local/go (official layout), symlinks into /usr/local/bin,
# and removes any apt-managed Go that would shadow it. Must be run as root.
# Sources the shared lib for logging/plumbing; the go.dev logic stays local.
#
#   sudo ./install_go.sh
_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/install_common.sh"
# shellcheck source=lib/install_common.sh
. "$_LIB"
ic_strict

IC_TOOL_NAME=go
IC_TOOL_DESC="Go toolchain (go.dev latest stable)"
IC_HELP_EXTRA="
Notes: must run as root (sudo). Installs to /usr/local/go, symlinks into
/usr/local/bin, and removes apt-managed golang-go/golang that would shadow it."

GO_ROOT_BASE="/usr/local"
GOROOT="${GO_ROOT_BASE}/go"
BIN_DIR="/usr/local/bin"

ic_parse_args "$@"

[[ $EUID -eq 0 ]] || ic_die "This script must be run as root. Try: sudo $0"
ic_require curl

case "$(uname -s)" in
    Linux)  OS="linux" ;;
    Darwin) OS="darwin" ;;
    *)      ic_die "Unsupported OS: $(uname -s)" ;;
esac
case "$(uname -m)" in
    x86_64|amd64)  ARCH="amd64" ;;
    aarch64|arm64) ARCH="arm64" ;;
    armv6l)        ARCH="armv6l" ;;
    i686|i386)     ARCH="386" ;;
    *)             ic_die "Unsupported architecture: $(uname -m)" ;;
esac

ic_info "Checking for the latest Go release..."
LATEST_VERSION=$(curl -fsSL "https://go.dev/VERSION?m=text" | head -n1)
[[ "$LATEST_VERSION" == go* ]] || ic_die "Could not determine the latest Go version (got: '$LATEST_VERSION')."

if [[ -x "${GOROOT}/bin/go" ]]; then
    CURRENT_VERSION=$("${GOROOT}/bin/go" version | awk '{print $3}')
    if [[ "$CURRENT_VERSION" == "$LATEST_VERSION" && "$FORCE" != "true" ]]; then
        ic_info "Go ${CURRENT_VERSION#go} is already up to date."
        exit 0
    fi
    ic_info "Upgrading Go ${CURRENT_VERSION#go} -> ${LATEST_VERSION#go}"
else
    ic_info "Installing Go ${LATEST_VERSION#go}"
fi

if [[ "$DRY_RUN" == "true" ]]; then
    ic_info "[DRY-RUN] would download ${LATEST_VERSION}.${OS}-${ARCH}.tar.gz and install to ${GOROOT}"
    exit 0
fi

ic_mktemp
TARBALL="${LATEST_VERSION}.${OS}-${ARCH}.tar.gz"
ic_download "https://go.dev/dl/${TARBALL}" "${IC_TMP_DIR}/${TARBALL}"

ic_info "Verifying checksum..."
EXPECTED_SHA=$(curl -fsSL "https://go.dev/dl/?mode=json&include=all" \
    | grep -A4 "\"filename\": \"${TARBALL}\"" \
    | grep -m1 '"sha256"' \
    | sed -E 's/.*"sha256": "([0-9a-f]+)".*/\1/')
if [[ -n "$EXPECTED_SHA" ]]; then
    ACTUAL_SHA=$(sha256sum "${IC_TMP_DIR}/${TARBALL}" | awk '{print $1}')
    [[ "$ACTUAL_SHA" == "$EXPECTED_SHA" ]] \
        || ic_die "Checksum mismatch for ${TARBALL} (expected ${EXPECTED_SHA}, got ${ACTUAL_SHA})."
    ic_info "Checksum OK."
else
    ic_warn "Could not fetch expected checksum; skipping verification."
fi

ic_info "Removing any previous install at ${GOROOT}..."
rm -rf "$GOROOT"
ic_info "Extracting to ${GO_ROOT_BASE}..."
tar -C "$GO_ROOT_BASE" -xzf "${IC_TMP_DIR}/${TARBALL}"

# An apt-installed Go (golang-go / golang) can shadow our /usr/local install.
if command -v apt-get >/dev/null 2>&1; then
    APT_GO_PKGS=()
    for pkg in golang-go golang; do
        if dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed"; then
            APT_GO_PKGS+=("$pkg")
        fi
    done
    if [[ ${#APT_GO_PKGS[@]} -gt 0 ]]; then
        ic_info "Removing apt-managed Go: ${APT_GO_PKGS[*]}"
        DEBIAN_FRONTEND=noninteractive apt-get remove -y "${APT_GO_PKGS[@]}"
        apt-get autoremove -y
    fi
fi

ic_info "Linking binaries into ${BIN_DIR}..."
ln -sf "${GOROOT}/bin/go" "${BIN_DIR}/go"
ln -sf "${GOROOT}/bin/gofmt" "${BIN_DIR}/gofmt"

hash -r 2>/dev/null || true
command -v go >/dev/null 2>&1 || ic_die "go not found on PATH after install."
ic_info "Installed: $(go version)"

ACTIVE_GO=$(command -v go)
if [[ "$ACTIVE_GO" != "${BIN_DIR}/go" ]]; then
    ic_warn "The active 'go' is ${ACTIVE_GO}, not ${BIN_DIR}/go."
    ic_warn "Ensure ${BIN_DIR} comes before $(dirname "$ACTIVE_GO") on your PATH."
fi
ic_info "Done."
