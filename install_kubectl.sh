#!/usr/bin/env bash
# install_kubectl.sh — install/upgrade kubectl (x86_64).
# Resolves the latest version via GitHub (kubernetes/kubernetes), downloads the
# verified binary from dl.k8s.io, verifies the .sha256 sidecar, backs up the
# existing binary, and installs to INSTALL_DIR. Bespoke logic (CDN layout,
# sidecar checksum, client-version parse, downgrade guard) stays local; the
# shared library provides logging, args, version helpers, download, install.
_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/install_common.sh"
# shellcheck source=lib/install_common.sh
. "$_LIB"
ic_strict

IC_TOOL_NAME=kubectl
IC_TOOL_DESC="Kubernetes CLI (kubernetes/kubernetes, binary from dl.k8s.io)"
IC_REPO=kubernetes/kubernetes
IC_HELP_EXTRA="
kubectl-specific:
  --allow-downgrade     Permit installing an older version than installed.
  KUBECTL_CDN_BASE      Binary CDN base (default: https://dl.k8s.io).
  KUBECTL_ALLOW_DOWNGRADE / KUBECTL_BACKUP  env fallbacks."

# --- kubectl-specific config (env fallbacks; flags via ic_parse_args) ---------
CDN_BASE="${KUBECTL_CDN_BASE:-https://dl.k8s.io}"
ALLOW_DOWNGRADE="${KUBECTL_ALLOW_DOWNGRADE:-false}"
DO_BACKUP="${KUBECTL_BACKUP:-true}"
OS="linux"
ARCH="amd64"

: "${REQ_VERSION:=${KUBECTL_VERSION:-latest}}"
_ktp="${KUBECTL_TARGET_PATH:-}"
: "${INSTALL_DIR:=${_ktp%/*}}"
: "${INSTALL_DIR:=/usr/local/bin}"
: "${DRY_RUN:=${KUBECTL_DRY_RUN:-false}}"
[[ "${KUBECTL_VERIFY_SHA256:-true}" == "false" ]] && : "${NO_VERIFY:=true}"

# Pull off the kubectl-only --allow-downgrade flag, then hand the rest to the
# shared parser.
_args=()
for a in "$@"; do
    case "$a" in
        --allow-downgrade) ALLOW_DOWNGRADE=true ;;
        *) _args+=("$a") ;;
    esac
done
ic_parse_args "${_args[@]}"

ic_require curl sha256sum
[[ "$(uname -s)" == "Linux" ]] || ic_die "This script supports Linux only."
[[ "$(uname -m)" =~ x86_64|amd64 ]] || ic_die "This script supports x86_64 only."

# --- bespoke helpers ----------------------------------------------------------
current_kubectl_version() {
    command -v kubectl >/dev/null 2>&1 || { echo ""; return; }
    kubectl version --client 2>/dev/null \
        | sed -nE 's/^Client Version:[[:space:]]*(v[0-9]+\.[0-9]+\.[0-9]+).*/\1/p'
}

verify_sidecar_sha256() {
    local file="$1" sha_url="$2"
    [[ "$DRY_RUN" == "true" ]] && { ic_info "[DRY-RUN] skipping checksum"; return; }
    [[ "${NO_VERIFY:-false}" == "true" ]] && { ic_warn "Skipping checksum verification"; return; }
    ic_info "Verifying checksum..."
    local expected actual
    expected="$(curl -fsSL "$sha_url" | awk '{print $1}')"
    actual="$(sha256sum "$file" | awk '{print $1}')"
    [[ "$expected" == "$actual" ]] || ic_die "Checksum mismatch!"
    ic_info "Checksum OK."
}

# --- main ---------------------------------------------------------------------
main() {
    local cur_ver desired
    cur_ver="$(current_kubectl_version || true)"
    if [[ -n "$cur_ver" ]]; then ic_info "Current kubectl: $cur_ver"; else ic_info "kubectl not found."; fi

    desired="$REQ_VERSION"
    if [[ "$desired" == "latest" || -z "$desired" ]]; then
        desired="$(ic_gh_latest_tag kubernetes/kubernetes '^v[0-9]+\.[0-9]+\.[0-9]+$')"
    fi
    ic_info "Desired version: $desired"

    if [[ -n "$cur_ver" && "$FORCE" != "true" ]]; then
        local cmp=0
        ic_vercmp "$cur_ver" "$desired" || cmp=$?
        case $cmp in
            0) ic_info "Already at target ($cur_ver)"; exit 0 ;;
            1) [[ "$ALLOW_DOWNGRADE" == "true" ]] || ic_die "Downgrade not allowed (use --allow-downgrade)" ;;
            2) ic_info "Upgrading $cur_ver -> $desired" ;;
        esac
    fi

    local bin_url sha_url
    bin_url="${CDN_BASE%/}/${desired}/bin/${OS}/${ARCH}/kubectl"
    sha_url="${bin_url}.sha256"

    if [[ "$DRY_RUN" == "true" ]]; then
        ic_info "[DRY-RUN] would download: $bin_url"
        ic_info "[DRY-RUN] would install kubectl to ${INSTALL_DIR}/kubectl"
        ic_info "Dry run complete."
        exit 0
    fi

    ic_mktemp
    local tmp_bin="${IC_TMP_DIR}/kubectl.new"
    ic_download "$bin_url" "$tmp_bin"
    verify_sidecar_sha256 "$tmp_bin" "$sha_url"

    [[ "$DO_BACKUP" == "true" ]] && ic_backup "${INSTALL_DIR}/kubectl"
    ic_install_bin "$tmp_bin" "${INSTALL_DIR}/kubectl"

    ic_rule
    "${INSTALL_DIR}/kubectl" version --client | grep -i 'client version' || true
    ic_rule
    ic_info "kubectl installation complete."
}

main
