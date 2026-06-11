#!/usr/bin/env bash
#
# install-python.sh
# Install or upgrade Python 3.13, 3.14, or 3.15 on Ubuntu 24.04 (incl. WSL)
# via the deadsnakes PPA. Idempotent: safe to re-run. Does NOT touch the
# system python3 (stays at 3.12).
#
# Must be run as root:
#   sudo ./install-python.sh                       # default: 3.14
#   sudo ./install-python.sh --version 3.13
#   sudo ./install-python.sh --version 3.15 --full
#   sudo ./install-python.sh -v 3.14 --venv ~/.venvs/py314
#   ./install-python.sh --help

_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/install_common.sh"
# shellcheck source=lib/install_common.sh
. "$_LIB"
ic_strict

# This script keeps its own arg parser: here --version selects a Python series
# (3.13/3.14/3.15), which is NOT the shared --version (a release tag) semantic.
IC_TOOL_NAME=python3

SUPPORTED_VERSIONS=("3.13" "3.14" "3.15")
VERSION="3.14"
FULL=0
VENV_DIR=""

# ---- helpers (logging via the shared library) ---------------------------
log()  { ic_info "$*"; }
warn() { ic_warn "$*"; }
die()  { ic_die "$*"; }

is_supported() {
    local v="$1" s
    for s in "${SUPPORTED_VERSIONS[@]}"; do
        [[ "$v" == "$s" ]] && return 0
    done
    return 1
}

# ---- arg parsing ---------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        -v|--version)
            VERSION="${2:-}"
            [[ -n "$VERSION" ]] || die "--version requires a value (one of: ${SUPPORTED_VERSIONS[*]})"
            shift 2
            ;;
        --full)
            FULL=1
            shift
            ;;
        --venv)
            VENV_DIR="${2:-}"
            [[ -n "$VENV_DIR" ]] || die "--venv requires a directory path"
            shift 2
            ;;
        -h|--help)
            sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            die "Unknown option: $1"
            ;;
    esac
done

is_supported "$VERSION" \
    || die "Unsupported version: $VERSION. Supported: ${SUPPORTED_VERSIONS[*]}"

# Build package list from VERSION
PY="python${VERSION}"
if [[ $FULL -eq 1 ]]; then
    PKG="${PY}-full"
else
    PKG="${PY}"
fi
EXTRAS=("${PY}-venv" "${PY}-dev")

# ---- require root --------------------------------------------------------
if [[ $EUID -ne 0 ]]; then
    die "This script must be run as root. Try: sudo $0 $*"
fi

# If invoked via sudo, remember the original user so --venv lands in their $HOME,
# not in /root, and is owned by them.
REAL_USER="${SUDO_USER:-root}"
if [[ "$REAL_USER" != "root" ]]; then
    REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)
else
    REAL_HOME="$HOME"
fi

# ---- sanity checks -------------------------------------------------------
command -v apt-get >/dev/null 2>&1 || die "This script requires apt (Debian/Ubuntu)."

if [[ -r /etc/os-release ]]; then
    . /etc/os-release
    log "Detected: ${PRETTY_NAME:-unknown}"
    if [[ "${ID:-}" != "ubuntu" ]]; then
        warn "Not Ubuntu (${ID:-?}); the deadsnakes PPA may not work."
    fi
fi

# ---- ensure deadsnakes PPA ----------------------------------------------
if ! grep -rqs '^deb .*deadsnakes' /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null; then
    log "Adding deadsnakes PPA..."
    apt-get update -y
    apt-get install -y software-properties-common
    add-apt-repository -y ppa:deadsnakes/ppa
else
    log "deadsnakes PPA already configured."
fi

# ---- install / upgrade ---------------------------------------------------
log "Refreshing package index..."
apt-get update -y

log "Target: Python ${VERSION}"
log "Installing/upgrading: $PKG ${EXTRAS[*]}"
apt-get install -y --only-upgrade "$PKG" "${EXTRAS[@]}" 2>/dev/null || true

if ! apt-get install -y "$PKG" "${EXTRAS[@]}"; then
    die "Package install failed. deadsnakes may not yet publish ${PY} for this Ubuntu release."
fi

# ---- verify --------------------------------------------------------------
command -v "$PY" >/dev/null 2>&1 || die "$PY not found on PATH after install."

INSTALLED_VERSION=$("$PY" --version 2>&1)
INSTALLED_PATH=$(command -v "$PY")
log "Installed: $INSTALLED_VERSION  ($INSTALLED_PATH)"

# ---- optional venv -------------------------------------------------------
if [[ -n "$VENV_DIR" ]]; then
    # Expand a leading ~ relative to the invoking user, not root.
    # shellcheck disable=SC2088  # matching a literal ~/ prefix, expanded below
    if [[ "$VENV_DIR" == "~/"* ]]; then
        VENV_DIR="$REAL_HOME/${VENV_DIR#~/}"
    fi

    if [[ -d "$VENV_DIR" ]]; then
        log "Venv already exists at $VENV_DIR — skipping create."
    else
        log "Creating venv at $VENV_DIR ..."
        if [[ "$REAL_USER" != "root" ]]; then
            # Create venv as the invoking user so they own it.
            sudo -u "$REAL_USER" "$PY" -m venv "$VENV_DIR"
            sudo -u "$REAL_USER" "$VENV_DIR/bin/python" -m pip install --upgrade pip >/dev/null
        else
            "$PY" -m venv "$VENV_DIR"
            "$VENV_DIR/bin/python" -m pip install --upgrade pip >/dev/null
        fi
    fi
    log "Venv ready. Activate with:  source $VENV_DIR/bin/activate"
fi

log "Done."
echo
echo "Quick start:"
echo "  $PY --version"
echo "  $PY -m venv ~/.venvs/py${VERSION/./} && source ~/.venvs/py${VERSION/./}/bin/activate"
