#!/usr/bin/env bash
# install_gitleaks.sh — install/upgrade gitleaks (gitleaks/gitleaks).
# Twist: arch token x64 for x86_64.
_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/install_common.sh"
# shellcheck source=lib/install_common.sh
. "$_LIB"
ic_strict

IC_TOOL_NAME=gitleaks
IC_TOOL_DESC="Secret scanner (gitleaks/gitleaks)"
IC_REPO=gitleaks/gitleaks
IC_ARCHIVE_TYPE=tar.gz
# shellcheck disable=SC2016  # template literal; expanded later by _ic_render
IC_ASSET_TMPL='gitleaks_${VER}_${OS}_${ARCH}.tar.gz'
IC_OS_CASE=lower
declare -A ARCH_MAP=( [x86_64]=x64 [aarch64]=arm64 [armv7l]=armv7 )
IC_LOCATOR='top:gitleaks'
IC_VERSION_CMD='version'

: "${REQ_VERSION:=${GITLEAKS_VERSION:-latest}}"
ic_parse_args "$@"
gh_binary_install
