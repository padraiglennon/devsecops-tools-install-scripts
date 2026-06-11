#!/usr/bin/env bash
# install_yq.sh — install/upgrade yq (mikefarah/yq).
# Twist: no version in asset name; archive binary is yq_<os>_<arch>, rename to yq.
_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/install_common.sh"
# shellcheck source=lib/install_common.sh
. "$_LIB"
ic_strict

IC_TOOL_NAME=yq
IC_TOOL_DESC="Command-line YAML processor (mikefarah/yq)"
IC_REPO=mikefarah/yq
IC_ARCHIVE_TYPE=tar.gz
# shellcheck disable=SC2016  # template literal; expanded later by _ic_render
IC_ASSET_TMPL='yq_${OS}_${ARCH}.tar.gz'
IC_OS_CASE=lower
declare -A ARCH_MAP=( [x86_64]=amd64 [aarch64]=arm64 [armv7l]=arm )
# shellcheck disable=SC2016  # template literal; expanded later by _ic_render
IC_LOCATOR='rename:yq_${OS}_${ARCH}'
IC_VERSION_CMD='--version'

: "${REQ_VERSION:=${YQ_VERSION:-latest}}"
ic_parse_args "$@"
gh_binary_install
