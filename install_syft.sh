#!/usr/bin/env bash
# install_syft.sh — install/upgrade syft (anchore/syft) from GitHub releases.
_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/install_common.sh"
# shellcheck source=lib/install_common.sh
. "$_LIB"
ic_strict

IC_TOOL_NAME=syft
IC_TOOL_DESC="SBOM generator (anchore/syft)"
IC_REPO=anchore/syft
IC_ARCHIVE_TYPE=tar.gz
# shellcheck disable=SC2016  # template literal; expanded later by _ic_render
IC_ASSET_TMPL='syft_${VER}_${OS}_${ARCH}.tar.gz'
IC_OS_CASE=lower
declare -A ARCH_MAP=( [x86_64]=amd64 [aarch64]=arm64 [armv7l]=armv7 )
IC_LOCATOR='top:syft'
IC_VERSION_CMD='version'

: "${REQ_VERSION:=${SYFT_VERSION:-latest}}"
ic_parse_args "$@"
gh_binary_install
