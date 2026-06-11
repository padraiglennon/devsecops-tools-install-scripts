#!/usr/bin/env bash
# install_jq.sh — install/upgrade jq (jqlang/jq).
# Twist: raw binary, tag format is jq-1.8.1 (not vX.Y.Z), arch armhf.
_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/install_common.sh"
# shellcheck source=lib/install_common.sh
. "$_LIB"
ic_strict

IC_TOOL_NAME=jq
IC_TOOL_DESC="Command-line JSON processor (jqlang/jq)"
IC_REPO=jqlang/jq
IC_ARCHIVE_TYPE=raw
# shellcheck disable=SC2016  # template literal; expanded later by _ic_render
IC_ASSET_TMPL='jq-${OS}-${ARCH}'
IC_OS_CASE=lower
declare -A ARCH_MAP=( [x86_64]=amd64 [aarch64]=arm64 [armv7l]=armhf )
IC_LOCATOR='self'
IC_VERSION_CMD='--version'
IC_TAG_REGEX='^jq-[0-9]'

: "${REQ_VERSION:=${JQ_VERSION:-latest}}"
ic_parse_args "$@"
gh_binary_install
