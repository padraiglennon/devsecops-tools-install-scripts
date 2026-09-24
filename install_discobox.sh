#!/usr/bin/env bash
# install_discobox.sh — install/upgrade discobox (discobox-ai/discobox).
# Twist: raw binary + SHA-256 verification against the digests stamped into the release's install.sh.
_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/install_common.sh"
# shellcheck source=lib/install_common.sh
. "$_LIB"
ic_strict

IC_TOOL_NAME=discobox
IC_TOOL_DESC="Discobox command line client (discobox-ai/discobox)"
IC_REPO=discobox-ai/discobox
IC_ARCHIVE_TYPE=raw
# shellcheck disable=SC2016  # template literal; expanded later by _ic_render
IC_ASSET_TMPL='discobox-${OS}-${ARCH}'
IC_OS_CASE=lower
declare -A ARCH_MAP=( [x86_64]=amd64 [aarch64]=arm64 )
IC_LOCATOR='self'
IC_VERSION_CMD='version'
IC_TAG_REGEX='^v[0-9]+\.[0-9]+\.[0-9]+'
IC_VERIFY_HOOK=discobox_verify

# discobox_verify <downloaded-file> <tmpdir> <ver_tag>  — SHA-256 check.
# Each release stamps the digest of every client binary into the install.sh it uploads.
discobox_verify() {
    local f="$1" d="$2" tag="$3"
    local script="https://github.com/${IC_REPO}/releases/download/${tag}/install.sh"
    command -v sha256sum >/dev/null 2>&1 || { ic_warn "sha256sum not found; skipping verification."; return 0; }
    ic_http_exists "$script" || { ic_warn "Release install.sh not available; skipping verification."; return 0; }
    ic_info "Verifying SHA-256 checksum..."
    ic_download "$script" "${d}/discobox_install.sh"
    grep -E "^[0-9a-f]{64}  $(basename "$f")\$" "${d}/discobox_install.sh" > "${d}/discobox_checksums.txt" \
        || ic_die "No checksum for $(basename "$f") in the release install.sh."
    ( cd "$d" && sha256sum -c discobox_checksums.txt ) || ic_die "Checksum verification failed!"
    ic_info "Checksum OK."
}

: "${REQ_VERSION:=${DISCOBOX_VERSION:-latest}}"
ic_parse_args "$@"
gh_binary_install
