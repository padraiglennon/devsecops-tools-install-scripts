#!/usr/bin/env bash
# install_actionlint.sh — install/upgrade actionlint (rhysd/actionlint).
_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/install_common.sh"
# shellcheck source=lib/install_common.sh
. "$_LIB"
ic_strict

IC_TOOL_NAME=actionlint
IC_TOOL_DESC="GitHub Actions workflow linter (rhysd/actionlint)"
IC_REPO=rhysd/actionlint
IC_ARCHIVE_TYPE=tar.gz
# shellcheck disable=SC2016  # template literal; expanded later by _ic_render
IC_ASSET_TMPL='actionlint_${VER}_${OS}_${ARCH}.tar.gz'
IC_OS_CASE=lower
declare -A ARCH_MAP=( [x86_64]=amd64 [aarch64]=arm64 [armv7l]=armv6 )
IC_LOCATOR='top:actionlint'
IC_VERSION_CMD='--version'

: "${REQ_VERSION:=${ACTIONLINT_VERSION:-latest}}"
ic_parse_args "$@"
gh_binary_install
