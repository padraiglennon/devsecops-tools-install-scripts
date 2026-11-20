#!/usr/bin/env bash
# install_claude.sh - install/upgrade the Claude Code CLI with the native
# installer flow of https://claude.ai/install.sh. Downloads the binary from
# downloads.claude.ai, checks it against the release manifest, then runs
# `claude install`, which sets up the launcher in ~/.local/bin and the version
# store in ~/.local/share/claude. No GitHub API call. Runs as a normal user:
# everything goes under $HOME.
_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/install_common.sh"
# shellcheck source=lib/install_common.sh
. "$_LIB"
ic_strict

IC_TOOL_NAME=claude
IC_TOOL_DESC="Claude Code CLI (native installer, downloads.claude.ai)"
IC_HELP_EXTRA="
claude-specific:
  --version accepts latest, stable or an exact version (for example 2.1.329).
  CLAUDE_VERSION    Env fallback for --version.
  --install-dir is not supported: 'claude install' chooses the location."

DOWNLOAD_BASE_URL="https://downloads.claude.ai/claude-code-releases"

: "${REQ_VERSION:=${CLAUDE_VERSION:-latest}}"
ic_parse_args "$@"

ic_require curl sha256sum
[[ $EUID -ne 0 ]] || ic_die "Claude Code installs under \$HOME; run the script as a normal user, not root."
[[ "$INSTALL_DIR" == "/usr/local/bin" ]] || ic_die "--install-dir is not supported; 'claude install' chooses the location."
[[ "$(uname -s)" == "Linux" ]] || ic_die "Unsupported OS: $(uname -s) (Linux only)."

# --- platform ----------------------------------------------------------------
case "$(uname -m)" in
    x86_64|amd64)  ARCH="x64" ;;
    aarch64|arm64) ARCH="arm64" ;;
    *)             ic_die "Unsupported architecture: $(uname -m)" ;;
esac
PLATFORM="linux-${ARCH}"
if command -v ldd >/dev/null 2>&1 && ldd --version 2>&1 | grep -qi musl; then
    PLATFORM="${PLATFORM}-musl"
fi
ic_info "Target platform: $PLATFORM"

# --- resolve version ---------------------------------------------------------
case "$REQ_VERSION" in
    latest|stable|"")
        CHANNEL="${REQ_VERSION:-latest}"
        VER=$(ic_curl -fsSL "${DOWNLOAD_BASE_URL}/${CHANNEL}") || ic_die "Failed to read the ${CHANNEL} channel."
        ;;
    *)
        CHANNEL=""
        VER=$(ic_strip_v "$REQ_VERSION")
        ;;
esac
[[ "$VER" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || ic_die "Invalid version from ${DOWNLOAD_BASE_URL}: '${VER}'"
ic_info "Target version: $VER"

if [[ "$FORCE" != "true" ]] && command -v claude >/dev/null 2>&1; then
    CUR=$(claude --version 2>/dev/null | awk '{print $1}' || true)
    if [[ "$CUR" == "$VER" ]]; then
        ic_info "claude is already at $VER."
        exit 0
    fi
fi

if [[ "$DRY_RUN" == "true" ]]; then
    ic_info "[DRY-RUN] would download ${DOWNLOAD_BASE_URL}/${VER}/${PLATFORM}/claude and run 'claude install ${CHANNEL:-$VER}'"
    exit 0
fi

# --- download + verify -------------------------------------------------------
# claude_manifest_checksum JSON PLATFORM - echo the SHA-256 of one platform.
claude_manifest_checksum() {
    local json
    json=$(printf '%s' "$1" | tr -d '\n\r\t')
    [[ "$json" =~ \""$2"\"[[:space:]]*:[[:space:]]*[{][^{}]*\"checksum\"[[:space:]]*:[[:space:]]*\"([a-f0-9]{64})\" ]] \
        || return 1
    printf '%s\n' "${BASH_REMATCH[1]}"
}

ic_mktemp
BIN="${IC_TMP_DIR}/claude-${VER}-${PLATFORM}"
ic_download "${DOWNLOAD_BASE_URL}/${VER}/${PLATFORM}/claude" "$BIN"

if [[ "$NO_VERIFY" != "true" ]]; then
    ic_info "Verifying checksum..."
    MANIFEST=$(ic_curl -fsSL "${DOWNLOAD_BASE_URL}/${VER}/manifest.json") || ic_die "Failed to download the manifest."
    EXPECTED=$(claude_manifest_checksum "$MANIFEST" "$PLATFORM") || ic_die "Platform $PLATFORM not found in the manifest."
    ACTUAL=$(sha256sum "$BIN" | awk '{print $1}')
    [[ "$ACTUAL" == "$EXPECTED" ]] || ic_die "Checksum verification failed"
fi

# --- install -----------------------------------------------------------------
chmod +x "$BIN"
ic_info "Running 'claude install'..."
( cd "$IC_TMP_DIR" && "$BIN" install "${CHANNEL:-$VER}" ) || ic_die "'claude install' failed."

ic_rule
"${HOME}/.local/bin/claude" --version
ic_rule
case ":${PATH}:" in
    *":${HOME}/.local/bin:"*) ;;
    *) ic_warn "${HOME}/.local/bin is not in PATH. Add it to your shell profile." ;;
esac
ic_info "claude installation complete."
