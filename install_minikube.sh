#!/usr/bin/env bash
# install_minikube.sh — install/upgrade minikube (x86_64) from GitHub releases.
# If minikube is running, warn + prompt to stop (or --force-stop); verify SHA256,
# back up, install, then auto-start (unless --no-start). Sources the shared lib
# for logging/plumbing; running-detection, auto-start, and downgrade guard stay local.
_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/install_common.sh"
# shellcheck source=lib/install_common.sh
. "$_LIB"
ic_strict

IC_TOOL_NAME=minikube
IC_TOOL_DESC="Local Kubernetes (kubernetes/minikube)"
IC_REPO=kubernetes/minikube
IC_HELP_EXTRA="
minikube-specific:
  --force-stop   Stop a running minikube without prompting.
  --no-start     Do not auto-start minikube after install.
  --allow-downgrade   Permit installing an older version."

GH_WEB_BASE="https://github.com/kubernetes/minikube"
ALLOW_DOWNGRADE="${MINIKUBE_ALLOW_DOWNGRADE:-false}"
DO_BACKUP="${MINIKUBE_BACKUP:-true}"
START_AFTER="${MINIKUBE_START_AFTER:-true}"
FORCE_STOP="${MINIKUBE_FORCE_STOP:-false}"
MINIKUBE_TIMEOUT_SECS="${MINIKUBE_TIMEOUT_SECS:-120}"
OS="linux"; ARCH="amd64"

: "${REQ_VERSION:=${MINIKUBE_VERSION:-latest}}"
_mtp="${MINIKUBE_TARGET_PATH:-}"
: "${INSTALL_DIR:=${_mtp%/*}}"
: "${INSTALL_DIR:=/usr/local/bin}"
: "${DRY_RUN:=${MINIKUBE_DRY_RUN:-false}}"
[[ "${MINIKUBE_VERIFY_SHA256:-true}" == "false" ]] && : "${NO_VERIFY:=true}"

# Pull off minikube-only flags, hand the rest to the shared parser.
_args=()
for a in "$@"; do
    case "$a" in
        --force-stop)      FORCE_STOP=true ;;
        --no-start)        START_AFTER=false ;;
        --allow-downgrade) ALLOW_DOWNGRADE=true ;;
        *) _args+=("$a") ;;
    esac
done
ic_parse_args "${_args[@]}"

ic_require curl sha256sum
[[ "$(uname -s)" == "Linux" ]] || ic_die "Linux only."
[[ "$(uname -m)" =~ x86_64|amd64 ]] || ic_die "x86_64 only."

has_timeout() { command -v timeout >/dev/null 2>&1; }
run_to() { local s="$1"; shift; if has_timeout; then timeout "$s" "$@"; else "$@"; fi; }

current_minikube_version() {
    command -v minikube >/dev/null 2>&1 || { echo ""; return 0; }
    run_to "$MINIKUBE_TIMEOUT_SECS" minikube version --short 2>/dev/null | head -n1 | tr -d '[:space:]'
}
is_minikube_running() {
    command -v minikube >/dev/null 2>&1 || return 1
    run_to "$MINIKUBE_TIMEOUT_SECS" minikube status 2>/dev/null | grep -qi 'Running'
}

main() {
    local cur_ver desired
    cur_ver="$(current_minikube_version || true)"
    if [[ -n "$cur_ver" ]]; then ic_info "Current minikube: $cur_ver"; else ic_info "minikube not found."; fi

    desired="$REQ_VERSION"
    if [[ "$desired" == "latest" || -z "$desired" ]]; then
        desired="$(ic_gh_latest_tag kubernetes/minikube '^v[0-9]+\.[0-9]+\.[0-9]+$' 2>/dev/null || echo latest)"
    fi
    [[ "$desired" != "latest" && ! "$desired" =~ ^v ]] && desired="v${desired}"
    ic_info "Desired version: $desired"

    if [[ -n "$cur_ver" && "$desired" != "latest" && "$FORCE" != "true" ]]; then
        local cmp=0
        ic_vercmp "$cur_ver" "$desired" || cmp=$?
        case $cmp in
            0) ic_info "Already at target ($cur_ver). Nothing to do."; exit 0 ;;
            1) [[ "$ALLOW_DOWNGRADE" == "true" ]] || ic_die "Downgrade $cur_ver -> $desired not allowed (use --allow-downgrade)" ;;
            2) ic_info "Upgrade available: $cur_ver -> $desired" ;;
        esac
    fi

    # Build URLs (latest uses the /releases/latest/download path).
    local fname="minikube-${OS}-${ARCH}" base
    if [[ "$desired" == "latest" ]]; then
        base="${GH_WEB_BASE}/releases/latest/download"
    else
        base="${GH_WEB_BASE}/releases/download/${desired}"
    fi
    local bin_url="${base}/${fname}" sha_url="${base}/${fname}.sha256"

    if [[ "$DRY_RUN" == "true" ]]; then
        ic_info "[DRY-RUN] would download: $bin_url"
        ic_info "[DRY-RUN] would install minikube to ${INSTALL_DIR}/minikube"
        exit 0
    fi

    # If running, stop first.
    if is_minikube_running; then
        ic_warn "minikube appears to be RUNNING."
        if [[ "$FORCE_STOP" == "true" ]]; then
            ic_info "--force-stop — stopping..."
            run_to "$MINIKUBE_TIMEOUT_SECS" minikube stop || ic_warn "minikube stop failed/timeout; continuing"
        else
            read -rp "Stop minikube now? [y/N] " ans
            if [[ "${ans,,}" =~ ^y(es)?$ ]]; then
                run_to "$MINIKUBE_TIMEOUT_SECS" minikube stop || ic_warn "minikube stop failed/timeout; continuing"
            else
                ic_die "Upgrade aborted because minikube is running."
            fi
        fi
    fi

    ic_mktemp
    local tmp_bin="${IC_TMP_DIR}/minikube.new"
    ic_download "$bin_url" "$tmp_bin"

    if [[ "${NO_VERIFY:-false}" != "true" ]]; then
        ic_info "Verifying checksum..."
        local expected actual
        expected="$(curl -fsSL "$sha_url" | awk '{print $1}' | tr -d '[:space:]')"
        [[ "${#expected}" -eq 64 ]] || ic_die "Invalid checksum content"
        actual="$(sha256sum "$tmp_bin" | awk '{print $1}')"
        [[ "$expected" == "$actual" ]] || ic_die "Checksum mismatch"
        ic_info "Checksum OK."
    fi

    [[ "$DO_BACKUP" == "true" ]] && ic_backup "${INSTALL_DIR}/minikube"
    ic_install_bin "$tmp_bin" "${INSTALL_DIR}/minikube"

    local new_ver; new_ver="$("${INSTALL_DIR}/minikube" version --short 2>/dev/null || true)"
    [[ -n "$new_ver" ]] && ic_info "minikube now: $new_ver"

    if [[ "$START_AFTER" == "true" ]]; then
        ic_info "Starting minikube..."
        run_to "$MINIKUBE_TIMEOUT_SECS" minikube start || ic_die "minikube start failed"
    else
        ic_info "Auto-start disabled (--no-start)."
    fi
    ic_info "Done."
}

main
