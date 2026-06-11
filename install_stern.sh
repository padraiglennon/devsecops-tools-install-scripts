#!/usr/bin/env bash
# install_stern.sh — install/upgrade stern (stern/stern) from GitHub releases.
_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/install_common.sh"
# shellcheck source=lib/install_common.sh
. "$_LIB"
ic_strict

IC_TOOL_NAME=stern
IC_TOOL_DESC="Multi-pod log tailing for Kubernetes (stern/stern)"
IC_REPO=stern/stern
IC_ARCHIVE_TYPE=tar.gz
# shellcheck disable=SC2016  # template literal; expanded later by _ic_render
IC_ASSET_TMPL='stern_${VER}_${OS}_${ARCH}.tar.gz'
IC_OS_CASE=lower
declare -A ARCH_MAP=( [x86_64]=amd64 [aarch64]=arm64 [armv7l]=arm )
IC_LOCATOR='top:stern'
IC_VERSION_CMD='--version'

: "${REQ_VERSION:=${STERN_VERSION:-latest}}"
ic_parse_args "$@"
gh_binary_install
