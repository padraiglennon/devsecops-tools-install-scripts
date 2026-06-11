#!/usr/bin/env bash
# install_grype.sh — install/upgrade grype (anchore/grype) from GitHub releases.
_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/install_common.sh"
# shellcheck source=lib/install_common.sh
. "$_LIB"
ic_strict

IC_TOOL_NAME=grype
IC_TOOL_DESC="Vulnerability scanner (anchore/grype)"
IC_REPO=anchore/grype
IC_ARCHIVE_TYPE=tar.gz
# shellcheck disable=SC2016  # template literal; expanded later by _ic_render
IC_ASSET_TMPL='grype_${VER}_${OS}_${ARCH}.tar.gz'
IC_OS_CASE=lower
declare -A ARCH_MAP=( [x86_64]=amd64 [aarch64]=arm64 [armv7l]=armv7 )
IC_LOCATOR='top:grype'
IC_VERSION_CMD='version'

: "${REQ_VERSION:=${GRYPE_VERSION:-latest}}"
ic_parse_args "$@"
gh_binary_install
