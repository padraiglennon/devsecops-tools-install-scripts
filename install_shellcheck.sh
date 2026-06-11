#!/usr/bin/env bash
# install_shellcheck.sh — install/upgrade shellcheck (koalaman/shellcheck).
# Twist: .tar.xz archive, binary in a versioned subdir, x86_64/aarch64 not remapped.
_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/install_common.sh"
# shellcheck source=lib/install_common.sh
. "$_LIB"
ic_strict

IC_TOOL_NAME=shellcheck
IC_TOOL_DESC="Shell script linter (koalaman/shellcheck)"
IC_REPO=koalaman/shellcheck
IC_ARCHIVE_TYPE=tar.xz
# shellcheck disable=SC2016  # template literal; expanded later by _ic_render
IC_ASSET_TMPL='shellcheck-${VER_TAG}.${OS}.${ARCH}.tar.xz'
IC_OS_CASE=lower
declare -A ARCH_MAP=( [x86_64]=x86_64 [aarch64]=aarch64 [armv7l]=armv6hf )
# shellcheck disable=SC2016  # template literal; expanded later by _ic_render
IC_LOCATOR='subdir:shellcheck-${VER_TAG}/shellcheck'
IC_VERSION_CMD='--version'

: "${REQ_VERSION:=${SHELLCHECK_VERSION:-latest}}"
ic_parse_args "$@"
gh_binary_install
