# shellcheck shell=bash
# install_common.sh — shared library for ~/bin/install_*.sh scripts.
#
# Sourced, never executed. Provides logging, OS/arch detection, GitHub release
# resolution, version comparison, download/extract/install helpers, a standard
# CLI flag parser, and a declarative entrypoint (gh_binary_install) that drives
# the "install a GitHub-released binary" family from a handful of variables.
#
# Source it from a tool script with a BASH_SOURCE-anchored path so it resolves
# under both bare invocation and `sudo ./script`:
#
#   _LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/install_common.sh"
#   . "$_LIB"
#   ic_strict
#
# Requires bash 4.3+ (namerefs). The host is bash 5.2.

# ---------------------------------------------------------------------------
# Strict mode + bootstrap
# ---------------------------------------------------------------------------
ic_strict() {
    set -euo pipefail
    IFS=$'\n\t'
    ic_trap_interrupt
}

# ic_trap_interrupt - make Ctrl-C (SIGINT) / SIGTERM abort the script cleanly:
# print a notice, then re-raise with the signal's default disposition so the
# script exits 130 (INT) / 143 (TERM) and any EXIT trap (e.g. ic_mktemp's
# temp-dir cleanup) still runs. Called by ic_strict so every lib-backed script
# gets it automatically. Safe to call directly from scripts that skip ic_strict.
ic_trap_interrupt() {
    trap '_ic_on_signal INT'  INT
    trap '_ic_on_signal TERM' TERM
}

_ic_on_signal() {
    local sig="$1"
    echo >&2
    echo "Interrupted - stopping." >&2
    trap - "$sig"
    kill -"$sig" "$$"
}

# ic_require cmd...  — die unless every named command is on PATH.
ic_require() {
    local missing=()
    local c
    for c in "$@"; do
        command -v "$c" >/dev/null 2>&1 || missing+=("$c")
    done
    if (( ${#missing[@]} > 0 )); then
        ic_die "Missing required command(s): ${missing[*]}"
    fi
}

# ic_mktemp  — create a temp dir and register an EXIT trap that removes it
# unless KEEP_TMP=true. Sets IC_TMP_DIR in the CALLER's shell (do NOT call via
# command substitution — the trap would fire in the subshell and delete the dir
# immediately). Read the path from $IC_TMP_DIR after calling.
ic_mktemp() {
    IC_TMP_DIR=$(mktemp -d -t "${IC_TOOL_NAME:-install}-XXXXXX")
    trap '_ic_cleanup_tmp' EXIT
}

_ic_cleanup_tmp() {
    if [[ "${KEEP_TMP:-false}" == "true" ]]; then
        ic_info "Keeping temp dir: ${IC_TMP_DIR:-}"
        return
    fi
    [[ -n "${IC_TMP_DIR:-}" && -d "${IC_TMP_DIR}" ]] && rm -rf "${IC_TMP_DIR}"
}

# ---------------------------------------------------------------------------
# Logging — one leveled model, gated by LOG_LEVEL, written to stderr.
# ---------------------------------------------------------------------------
LOG_LEVEL="${LOG_LEVEL:-INFO}"
IC_LOG_TIMESTAMPS="${IC_LOG_TIMESTAMPS:-false}"

_ic_level_to_int() {
    case "$1" in
        DEBUG)        echo 10 ;;
        INFO)         echo 20 ;;
        WARN|WARNING) echo 30 ;;
        ERROR)        echo 40 ;;
        *)            echo 20 ;;
    esac
}

ic_log() {
    local lvl="$1"; shift
    local want cur
    want=$(_ic_level_to_int "$lvl")
    cur=$(_ic_level_to_int "$LOG_LEVEL")
    (( want >= cur )) || return 0
    if [[ "$IC_LOG_TIMESTAMPS" == "true" ]]; then
        printf '%s %s %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$lvl" "$*" >&2
    else
        printf '[%s] %s\n' "$lvl" "$*" >&2
    fi
}

ic_debug() { ic_log DEBUG "$@"; }
ic_info()  { ic_log INFO  "$@"; }
ic_warn()  { ic_log WARN  "$@"; }
ic_error() { ic_log ERROR "$@"; }
ic_die()   { ic_error "$@"; exit 1; }
ic_rule()  { echo "---------------------------------------"; }

# ---------------------------------------------------------------------------
# OS / arch detection
# ---------------------------------------------------------------------------
# ic_os [caps]  — echo OS token. Default lowercase ("linux"); "caps" gives the
# raw `uname -s` ("Linux") for tools like trivy/hadolint.
ic_os() {
    if [[ "${1:-}" == "caps" ]]; then
        uname -s
    else
        uname -s | tr '[:upper:]' '[:lower:]'
    fi
}

# ic_map_arch -A MAPVAR  — map `uname -m` through a caller-declared associative
# array (passed by name). Dies on an unmapped arch; "no-map" tools declare
# explicit identity entries (e.g. [x86_64]=x86_64).
ic_map_arch() {
    [[ "$1" == "-A" ]] || ic_die "ic_map_arch: usage: ic_map_arch -A MAPVAR"
    local -n _map="$2"
    local raw
    raw=$(uname -m)
    if [[ -n "${_map[$raw]:-}" ]]; then
        printf '%s\n' "${_map[$raw]}"
    else
        ic_die "Unsupported architecture: $raw (no entry in ${2})"
    fi
}

# ---------------------------------------------------------------------------
# Release resolution + version compare
# ---------------------------------------------------------------------------
GH_API_BASE="${GH_API_BASE:-https://api.github.com}"
GH_TOKEN="${GH_TOKEN:-}"
IC_CONNECT_TIMEOUT="${IC_CONNECT_TIMEOUT:-30}"
IC_READ_TIMEOUT="${IC_READ_TIMEOUT:-300}"

# ic_gh_latest_tag REPO [tag_regex]  — echo the latest release tag. Anchored,
# minified-JSON-safe extraction. Honors GH_TOKEN. Validates against tag_regex
# if given.
ic_gh_latest_tag() {
    local repo="$1" regex="${2:-}"
    local headers=("-H" "Accept: application/vnd.github+json")
    [[ -n "$GH_TOKEN" ]] && headers+=("-H" "Authorization: Bearer ${GH_TOKEN}")
    local url="${GH_API_BASE%/}/repos/${repo}/releases/latest"
    local body tag
    # Capture first, then parse — avoids `grep -m1` closing the pipe early
    # (curl exit 23 under pipefail).
    body=$(curl -fsSL --connect-timeout "$IC_CONNECT_TIMEOUT" --max-time "$IC_READ_TIMEOUT" \
            "${headers[@]}" "$url") || true
    tag=$(printf '%s' "$body" \
          | grep -oE '"tag_name"[[:space:]]*:[[:space:]]*"[^"]+"' \
          | head -n1 \
          | sed -E 's/.*"([^"]+)"$/\1/')
    [[ -n "$tag" ]] || ic_die "Failed to resolve latest release for ${repo} (rate-limited or network error?)."
    if [[ -n "$regex" && ! "$tag" =~ $regex ]]; then
        ic_die "Resolved tag '${tag}' for ${repo} does not match expected pattern /${regex}/."
    fi
    printf '%s\n' "$tag"
}

# ic_strip_v STR  — normalize a tag to a bare semver. Handles v1.2.3 and
# jq-1.8.1 → 1.8.1.
ic_strip_v() {
    printf '%s\n' "$1" | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n1
}

# ic_vercmp A B  — return 0 if A==B, 1 if A>B, 2 if A<B.
# Callers under `set -e` MUST guard: `ic_vercmp x y || rc=$?`.
ic_vercmp() {
    local a b i IFS=.
    read -ra a <<< "$(ic_strip_v "$1")"
    read -ra b <<< "$(ic_strip_v "$2")"
    for i in 0 1 2; do
        local ai="${a[$i]:-0}" bi="${b[$i]:-0}"
        (( ai > bi )) && return 1
        (( ai < bi )) && return 2
    done
    return 0
}

# ---------------------------------------------------------------------------
# Download
# ---------------------------------------------------------------------------
# ic_download URL DEST  — download with curl -fL; die on failure. In dry-run,
# log and create an empty placeholder.
ic_download() {
    local url="$1" dest="$2"
    ic_info "Downloading: $url"
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        : > "$dest"
        return 0
    fi
    curl -fL --connect-timeout "$IC_CONNECT_TIMEOUT" --max-time "$IC_READ_TIMEOUT" \
        -o "$dest" "$url" || ic_die "Download failed: $url"
}

# ic_http_exists URL  — HEAD check; return status.
ic_http_exists() {
    curl -sIf --connect-timeout "$IC_CONNECT_TIMEOUT" "$1" >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
# Extract + locate (polymorphic)
# ---------------------------------------------------------------------------
# ic_extract_locate ARCHIVE DESTDIR TYPE LOCATOR  — extract by TYPE then echo
# the absolute path of the produced binary per LOCATOR.
#   TYPE    ∈ raw | tar.gz | tar.xz | zip | gz
#   LOCATOR ∈ top:<name> | subdir:<relpath> | rename:<extracted-name> | self
ic_extract_locate() {
    local archive="$1" dest="$2" type="$3" locator="$4"

    case "$type" in
        raw)    : ;;  # nothing to extract; binary is the archive itself
        tar.gz) tar -xzf "$archive" -C "$dest" ;;
        tar.xz) tar -xJf "$archive" -C "$dest" ;;
        zip)    unzip -q -o "$archive" -d "$dest" ;;
        gz)     gunzip -c "$archive" > "${dest}/$(basename "${archive%.gz}")" ;;
        *)      ic_die "Unknown archive type: $type" ;;
    esac

    local mode="${locator%%:*}" arg="${locator#*:}"
    local path
    case "$mode" in
        self)   path="$archive" ;;
        top)    path="${dest}/${arg}" ;;
        subdir) path="${dest}/${arg}" ;;
        rename) path="${dest}/${arg}" ;;
        *)      ic_die "Unknown locator mode: $mode" ;;
    esac

    [[ -e "$path" ]] || ic_die "Expected binary not found after extract: $path"
    printf '%s\n' "$path"
}

# ---------------------------------------------------------------------------
# Privileged install
# ---------------------------------------------------------------------------
IC_AUTO_SUDO="${IC_AUTO_SUDO:-true}"

# ic_install_bin SRC DST  — chmod +x and move into place. Tries without sudo
# first (succeeds when EUID==0 or DST dir is user-writable); falls back to sudo.
# Dry-run aware.
ic_install_bin() {
    local src="$1" dst="$2"
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        ic_info "[DRY-RUN] would install to ${dst}"
        return 0
    fi
    chmod +x "$src"
    local dstdir
    dstdir=$(dirname "$dst")

    if [[ -w "$dstdir" || $EUID -eq 0 ]]; then
        mkdir -p "$dstdir"
        mv -f "$src" "$dst"
        ic_info "Installed: $dst"
        return 0
    fi

    if [[ "$IC_AUTO_SUDO" == "true" ]]; then
        sudo mkdir -p "$dstdir"
        sudo mv -f "$src" "$dst"
        sudo chmod +x "$dst"
        ic_info "Installed: $dst (via sudo)"
        return 0
    fi

    ic_die "No write permission for ${dstdir} and IC_AUTO_SUDO is off."
}

# ic_backup PATH  — timestamped backup of an existing file before overwrite.
# Falls back to ~/.local/share/<tool>-backups if the target dir isn't writable.
ic_backup() {
    local target="$1"
    [[ -e "$target" ]] || return 0
    [[ "${DRY_RUN:-false}" == "true" ]] && return 0
    local ts backup
    ts=$(date '+%Y%m%d-%H%M%S')
    backup="${target}.bak.${ts}"
    if cp -p "$target" "$backup" 2>/dev/null; then
        ic_info "Backup: $backup"
    else
        local alt="${HOME}/.local/share/${IC_TOOL_NAME:-bin}-backups"
        mkdir -p "$alt"
        backup="${alt}/$(basename "$target").bak.${ts}"
        cp -p "$target" "$backup" || ic_die "Backup failed (even fallback)."
        ic_warn "No permission in $(dirname "$target"); backup stored at $backup"
    fi
}

# ---------------------------------------------------------------------------
# CLI flag parser + help
# ---------------------------------------------------------------------------
# Standard variables (a tool seeds env fallbacks BEFORE calling ic_parse_args;
# flags override only when actually present):
#   REQ_VERSION  INSTALL_DIR  DRY_RUN  FORCE  NO_VERIFY  KEEP_TMP
ic_parse_args() {
    : "${REQ_VERSION:=latest}"
    : "${INSTALL_DIR:=/usr/local/bin}"
    : "${DRY_RUN:=false}"
    : "${FORCE:=false}"
    : "${NO_VERIFY:=false}"
    : "${KEEP_TMP:=false}"

    while [[ $# -gt 0 ]]; do
        local arg="$1" val=""
        if [[ "$arg" == *=* ]]; then
            val="${arg#*=}"; arg="${arg%%=*}"
        fi
        case "$arg" in
            -v|--version)     REQ_VERSION="${val:-$2}"; [[ -z "$val" ]] && shift ;;
            -d|--install-dir) INSTALL_DIR="${val:-$2}"; [[ -z "$val" ]] && shift ;;
            -n|--dry-run)     DRY_RUN=true ;;
            -f|--force)       FORCE=true ;;
            --no-verify)      NO_VERIFY=true ;;
            --keep-tmp)       KEEP_TMP=true ;;
            -h|--help)        ic_help; exit 0 ;;
            *) ic_die "Unknown argument: $1 (try --help)" ;;
        esac
        shift
    done
}

ic_help() {
    cat <<EOF
${IC_TOOL_NAME:-installer} — ${IC_TOOL_DESC:-install/upgrade a tool}
${IC_REPO:+Source: ${IC_REPO}}

Usage:
  $(basename "${0}") [options]

Options:
  -v, --version <ver|latest>  Version to install (default: latest)
  -d, --install-dir <path>    Install directory (default: /usr/local/bin)
  -n, --dry-run               Resolve and report, but don't install
  -f, --force                 Reinstall even if already up to date
      --no-verify             Skip checksum/payload verification (if supported)
      --keep-tmp              Keep the temp download dir
  -h, --help                  Show this help

Environment fallbacks (flags take precedence):
  Version via the tool's *_VERSION var; INSTALL_DIR; *_DRY_RUN; LOG_LEVEL.
${IC_HELP_EXTRA:-}
EOF
}

# ---------------------------------------------------------------------------
# Declarative entrypoint for the GitHub-binary family
# ---------------------------------------------------------------------------
# Renders an asset/locator template that references ${VER} ${VER_TAG} ${OS}
# ${ARCH} ${TOOL}. Templates are author-fixed literals; values are shell-safe
# tokens (semver / arch / os), so controlled eval is acceptable here.
_ic_render() {
    local tmpl="$1"
    local VER="$2" VER_TAG="$3" OS="$4" ARCH="$5" TOOL="${6:-}"
    eval "printf '%s' \"$tmpl\""
}

# gh_binary_install  — drive a simple-family install from declared IC_* vars.
gh_binary_install() {
    ic_require curl tar

    local ver_tag ver
    if [[ "$REQ_VERSION" == "latest" || -z "$REQ_VERSION" ]]; then
        ver_tag=$(ic_gh_latest_tag "$IC_REPO" "${IC_TAG_REGEX:-}")
    else
        ver_tag="$REQ_VERSION"
    fi
    ver=$(ic_strip_v "$ver_tag")
    ic_info "${IC_TOOL_NAME}: target ${ver_tag}"

    # Version-skip check (single-binary tools; primary tool for multi).
    if [[ "$FORCE" != "true" ]] && command -v "$IC_TOOL_NAME" >/dev/null 2>&1; then
        local cur
        # shellcheck disable=SC2086  # IC_VERSION_CMD is an intentional word list
        cur=$(ic_strip_v "$("$IC_TOOL_NAME" $IC_VERSION_CMD 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1)")
        if [[ -n "$cur" && "$cur" == "$ver" ]]; then
            ic_info "${IC_TOOL_NAME} already at ${ver_tag}. Nothing to do."
            return 0
        fi
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        local os arch
        if [[ "$IC_OS_CASE" == caps ]]; then os=$(ic_os caps); else os=$(ic_os); fi
        arch=$(ic_map_arch -A ARCH_MAP)
        local tools=("${IC_MULTI[@]:-$IC_TOOL_NAME}")
        local t
        for t in "${tools[@]}"; do
            local asset url
            asset=$(_ic_render "$IC_ASSET_TMPL" "$ver" "$ver_tag" "$os" "$arch" "$t")
            url="https://github.com/${IC_REPO}/releases/download/${ver_tag}/${asset}"
            ic_info "[DRY-RUN] would download: $url"
            ic_info "[DRY-RUN] would install ${t} to ${INSTALL_DIR}/${t}"
        done
        return 0
    fi

    local os arch
    arch=$(ic_map_arch -A ARCH_MAP)
    if [[ "$IC_OS_CASE" == caps ]]; then os=$(ic_os caps); else os=$(ic_os); fi

    ic_mktemp
    local tmp="$IC_TMP_DIR"

    local tools=("${IC_MULTI[@]:-$IC_TOOL_NAME}")
    local t
    for t in "${tools[@]}"; do
        local asset url dlpath bin locator
        asset=$(_ic_render "$IC_ASSET_TMPL" "$ver" "$ver_tag" "$os" "$arch" "$t")
        url="https://github.com/${IC_REPO}/releases/download/${ver_tag}/${asset}"
        dlpath="${tmp}/${asset}"
        ic_download "$url" "$dlpath"

        # Optional per-tool verification hook: HOOK <file> <tmpdir> <ver_tag>
        if [[ "$NO_VERIFY" != "true" && -n "${IC_VERIFY_HOOK:-}" ]]; then
            "$IC_VERIFY_HOOK" "$dlpath" "$tmp" "$ver_tag"
        fi

        locator=$(_ic_render "$IC_LOCATOR" "$ver" "$ver_tag" "$os" "$arch" "$t")
        bin=$(ic_extract_locate "$dlpath" "$tmp" "$IC_ARCHIVE_TYPE" "$locator")
        ic_install_bin "$bin" "${INSTALL_DIR}/${t}"
    done

    ic_rule
    # shellcheck disable=SC2086  # IC_VERSION_CMD is an intentional word list
    "${INSTALL_DIR}/${IC_TOOL_NAME}" $IC_VERSION_CMD || true
    ic_rule
    ic_info "${IC_TOOL_NAME} installation complete."
}
