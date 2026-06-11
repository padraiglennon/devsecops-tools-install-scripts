#!/usr/bin/env bash
# install_hadolint.sh — install/upgrade hadolint (hadolint/hadolint).
# Twist: raw binary (no archive), capitalized OS, x86_64 not remapped.
_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/install_common.sh"
# shellcheck source=lib/install_common.sh
. "$_LIB"
ic_strict

IC_TOOL_NAME=hadolint
IC_TOOL_DESC="Dockerfile linter (hadolint/hadolint)"
IC_REPO=hadolint/hadolint
IC_ARCHIVE_TYPE=raw
# shellcheck disable=SC2016  # template literal; expanded later by _ic_render
IC_ASSET_TMPL='hadolint-${OS}-${ARCH}'
IC_OS_CASE=caps
declare -A ARCH_MAP=( [x86_64]=x86_64 [aarch64]=arm64 )
IC_LOCATOR='self'
IC_VERSION_CMD='--version'

: "${REQ_VERSION:=${HADOLINT_VERSION:-latest}}"
ic_parse_args "$@"
gh_binary_install
