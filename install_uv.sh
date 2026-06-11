#!/usr/bin/env bash
# install_uv.sh — install/upgrade uv (astral-sh/uv) from GitHub releases.
# Bespoke: glibc/musl target suffix, checksum sidecar, find-based locator, and
# a permission-aware install-dir fallback. Sources the shared lib for logging/
# plumbing; the platform/target/install logic stays local.
_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/install_common.sh"
# shellcheck source=lib/install_common.sh
. "$_LIB"
ic_strict

IC_TOOL_NAME=uv
IC_TOOL_DESC="Fast Python package/project manager (astral-sh/uv)"
IC_REPO=astral-sh/uv
DEFAULT_INSTALL_DIR="/usr/local/bin"

: "${REQ_VERSION:=${UV_VERSION:-latest}}"
ic_parse_args "$@"

ic_require curl tar sha256sum awk find

# --- platform / target -------------------------------------------------------
case "$(uname -s)" in
    Linux)  OS_TYPE="unknown-linux" ;;
    Darwin) OS_TYPE="apple-darwin" ;;
    *)      ic_die "Unsupported OS: $(uname -s)" ;;
esac
case "$(uname -m)" in
    x86_64|amd64)  ARCH_TYPE="x86_64" ;;
    aarch64|arm64) ARCH_TYPE="aarch64" ;;
    *)             ic_die "Unsupported architecture: $(uname -m)" ;;
esac
LIBC_SUFFIX=""
if [[ "$OS_TYPE" == "unknown-linux" ]]; then
    if command -v ldd >/dev/null 2>&1 && ldd --version 2>&1 | grep -qi musl; then
        LIBC_SUFFIX="-musl"; ic_info "Detected musl libc"
    else
        LIBC_SUFFIX="-gnu"; ic_info "Detected glibc"
    fi
fi
TARGET="${ARCH_TYPE}-${OS_TYPE}${LIBC_SUFFIX}"
ic_info "Target platform: $TARGET"

# --- install dir (honor --install-dir, else permission-aware fallback) --------
if [[ -n "${INSTALL_DIR:-}" && "$INSTALL_DIR" != "/usr/local/bin" ]]; then
    : # explicit --install-dir / env override; ic_install_bin handles sudo
elif [[ -w "$DEFAULT_INSTALL_DIR" ]] || command -v sudo >/dev/null 2>&1; then
    INSTALL_DIR="$DEFAULT_INSTALL_DIR"
else
    INSTALL_DIR="${HOME}/.local/bin"; mkdir -p "$INSTALL_DIR"
    ic_info "Installing to user directory: $INSTALL_DIR"
fi

# --- resolve version ---------------------------------------------------------
if [[ "$REQ_VERSION" == "latest" || -z "$REQ_VERSION" ]]; then
    VER_TAG=$(ic_gh_latest_tag "$IC_REPO")
else
    VER_TAG="$REQ_VERSION"
fi
VER=$(ic_strip_v "$VER_TAG")
ic_info "Latest version available: $VER"

if [[ "$FORCE" != "true" ]] && command -v uv >/dev/null 2>&1; then
    CUR=$(ic_strip_v "$(uv --version 2>/dev/null | awk '{print $2}')")
    if [[ -n "$CUR" && "$CUR" == "$VER" ]]; then
        ic_info "uv is already up to date ($VER)."
        exit 0
    fi
fi

if [[ "$DRY_RUN" == "true" ]]; then
    ic_info "[DRY-RUN] would download uv-${TARGET}.tar.gz for ${VER_TAG} -> ${INSTALL_DIR}/uv"
    exit 0
fi

# --- download + verify + install ---------------------------------------------
ic_mktemp
ARCHIVE="uv-${TARGET}.tar.gz"
URL="https://github.com/${IC_REPO}/releases/download/${VER_TAG}/${ARCHIVE}"
ic_download "$URL" "${IC_TMP_DIR}/${ARCHIVE}"

if [[ "${NO_VERIFY:-false}" != "true" ]]; then
    ic_info "Verifying checksum..."
    ic_download "${URL}.sha256" "${IC_TMP_DIR}/${ARCHIVE}.sha256"
    ( cd "$IC_TMP_DIR" && sha256sum -c "${ARCHIVE}.sha256" ) || ic_die "Checksum verification failed"
fi

tar -xzf "${IC_TMP_DIR}/${ARCHIVE}" -C "$IC_TMP_DIR" || ic_die "Extraction failed"
UV_BIN="$(find "$IC_TMP_DIR" -type f -name uv -perm -111 | head -1)"
[[ -n "$UV_BIN" ]] || ic_die "Extracted uv binary not found"

ic_install_bin "$UV_BIN" "${INSTALL_DIR}/uv"

ic_rule
"${INSTALL_DIR}/uv" --version
ic_rule
ic_info "uv installation complete."
