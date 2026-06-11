#!/usr/bin/env bash
# install_trivy.sh — install/upgrade trivy (aquasecurity/trivy).
# Twist: capitalized OS (Linux), arch tokens 64bit/ARM64, dash in asset name.
_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/install_common.sh"
# shellcheck source=lib/install_common.sh
. "$_LIB"
ic_strict

IC_TOOL_NAME=trivy
IC_TOOL_DESC="Vulnerability/misconfig scanner (aquasecurity/trivy)"
IC_REPO=aquasecurity/trivy
IC_ARCHIVE_TYPE=tar.gz
# shellcheck disable=SC2016  # template literal; expanded later by _ic_render
IC_ASSET_TMPL='trivy_${VER}_${OS}-${ARCH}.tar.gz'
IC_OS_CASE=caps
declare -A ARCH_MAP=( [x86_64]=64bit [aarch64]=ARM64 [armv7l]=ARM )
IC_LOCATOR='top:trivy'
IC_VERSION_CMD='--version'

: "${REQ_VERSION:=${TRIVY_VERSION:-latest}}"
ic_parse_args "$@"
gh_binary_install
