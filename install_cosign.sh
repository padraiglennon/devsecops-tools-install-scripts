#!/usr/bin/env bash
# install_cosign.sh — install/upgrade cosign (sigstore/cosign).
# Twist: raw binary + payload sanity (size, ELF) + SHA-256 checksum verification.
_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/install_common.sh"
# shellcheck source=lib/install_common.sh
. "$_LIB"
ic_strict

IC_TOOL_NAME=cosign
IC_TOOL_DESC="Container signing/verification (sigstore/cosign)"
IC_REPO=sigstore/cosign
IC_ARCHIVE_TYPE=raw
# shellcheck disable=SC2016  # template literal; expanded later by _ic_render
IC_ASSET_TMPL='cosign-${OS}-${ARCH}'
IC_OS_CASE=lower
declare -A ARCH_MAP=( [x86_64]=amd64 [aarch64]=arm64 [armv7l]=arm )
IC_LOCATOR='self'
IC_VERSION_CMD='version'
IC_TAG_REGEX='^v[0-9]+\.[0-9]+\.[0-9]+'
IC_VERIFY_HOOK=cosign_verify

# cosign_verify <downloaded-file> <tmpdir> <ver_tag>  — payload sanity + checksum.
cosign_verify() {
    local f="$1" d="$2" tag="$3"
    local size
    size=$(stat -c '%s' "$f")
    (( size >= 1000000 )) || ic_die "Downloaded file is only ${size} bytes — not a real cosign binary."
    if command -v file >/dev/null 2>&1; then
        file "$f" | grep -q 'ELF' || ic_die "Downloaded file is not an ELF executable."
    fi
    local sums="https://github.com/${IC_REPO}/releases/download/${tag}/cosign_checksums.txt"
    if command -v sha256sum >/dev/null 2>&1 && ic_http_exists "$sums"; then
        ic_info "Verifying SHA-256 checksum..."
        ic_download "$sums" "${d}/cosign_checksums.txt"
        ( cd "$d" && grep " $(basename "$f")\$" cosign_checksums.txt | sha256sum -c - ) \
            || ic_die "Checksum verification failed!"
        ic_info "Checksum OK."
    else
        ic_warn "Checksum file not available; skipping verification."
    fi
}

: "${REQ_VERSION:=${COSIGN_VERSION:-latest}}"
ic_parse_args "$@"
gh_binary_install
